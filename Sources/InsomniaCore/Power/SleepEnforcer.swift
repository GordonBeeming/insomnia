// SleepEnforcer.swift — InsomniaCore
//
// Makes "only Insomnia keeps my Mac awake" true. While Insomnia is
// decaffeinated it (1) ends other `caffeinate` processes owned by the current
// user and (2) puts the Mac to sleep itself once the display is asleep and the
// user has been idle past the macOS sleep threshold. macOS can't cancel
// another process's assertion, so these are the two levers that exist.
//
// All decisions live in the pure `SleepEnforcer.decide` function; every system
// touchpoint (processes, idle state, sleep, remote sessions, wake time) is an
// injected protocol so tests never kill a process or sleep the Mac.

import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt
import IOKit.ps
import Darwin
#if canImport(AppKit)
import AppKit
#endif
import os

// MARK: - Injected Protocols

/// Finds and ends the current user's `caffeinate` processes.
public protocol ProcessControlling: Sendable {
    /// The current user's `/usr/bin/caffeinate` processes (excluding ours), with their start times.
    func caffeinateProcesses() -> [ProcessIdentity]
    /// Sends SIGTERM to the process if it is still the same caffeinate that was discovered.
    /// - Returns: `false` when the process was already gone, replaced by another process, or no longer ours to signal.
    /// - Throws: For any failure other than ESRCH.
    func terminate(_ process: ProcessIdentity) throws -> Bool
}

/// Reports how idle the user and display are.
public protocol IdleStateProviding: Sendable {
    /// Seconds since the last keyboard/mouse/trackpad input, or nil if unknown.
    func idleSeconds() -> TimeInterval?
    /// Whether every active display is asleep (false when that can't be determined).
    func isDisplayAsleep() -> Bool
    /// Seconds of idle after which macOS would sleep on its own for the current power
    /// source, or nil for "never" / unknown (no forced sleep then).
    func sleepThresholdSeconds() -> TimeInterval?
}

/// Triggers system sleep.
public protocol SystemSleeping: Sendable {
    /// Puts the Mac to sleep now.
    func sleepNow() throws
}

/// Detects a remote session that would be cut off by a forced sleep.
public protocol RemoteSessionDetecting: Sendable {
    /// True when an SSH login, SSH connection without a terminal, or Screen Sharing session is active.
    func isRemoteSessionActive() -> Bool
}

/// Tells how long ago the Mac last woke.
public protocol WakeTimeProviding: Sendable {
    /// Seconds since the last wake (or since launch if it hasn't slept), on a clock that keeps counting through sleep.
    func secondsSinceWake() -> TimeInterval
}

// MARK: - Decision Logic

// MARK: - Monotonic Clock

/// A clock that is immune to wall-clock changes and keeps counting while the Mac sleeps.
public enum MonotonicClock {
    /// Seconds on `CLOCK_MONOTONIC`, which (unlike `CLOCK_UPTIME_RAW`) includes time asleep.
    public static func seconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

/// One thing the enforcer should do in a pass.
public enum EnforcerAction: Equatable, Sendable {
    /// SIGTERM these caffeinate processes.
    case terminate([ProcessIdentity])
    /// Put the Mac to sleep.
    case sleepNow
}

/// Everything `SleepEnforcer.decide` needs; no system access happens inside the decision.
public struct EnforcerInput: Sendable {
    /// Whether Insomnia currently holds its own assertion.
    public var isCaffeinated: Bool
    /// The "Only Insomnia keeps my Mac awake" setting.
    public var settingEnabled: Bool
    /// Seconds since last user input, nil if unknown.
    public var idleSeconds: TimeInterval?
    /// Seconds since the last wake.
    public var secondsSinceWake: TimeInterval
    /// macOS sleep threshold in seconds, nil for never.
    public var thresholdSeconds: TimeInterval?
    /// Whether the display is asleep.
    public var displayAsleep: Bool
    /// Other processes' assertions, of every type.
    public var holders: [ForeignAssertion]
    /// The current user's `caffeinate` processes (terminated by the sweep, so never counted as blockers).
    public var caffeinatePids: [ProcessIdentity]
    /// Whether an SSH or Screen Sharing session is active.
    public var remoteSessionActive: Bool
    /// Seconds since the last forced sleep, nil if none this run.
    public var secondsSinceForcedSleep: TimeInterval?

    /// Creates an input record; every field is explicit so tests state their scenario.
    public init(
        isCaffeinated: Bool, settingEnabled: Bool, idleSeconds: TimeInterval?, secondsSinceWake: TimeInterval,
        thresholdSeconds: TimeInterval?, displayAsleep: Bool, holders: [ForeignAssertion],
        caffeinatePids: [ProcessIdentity], remoteSessionActive: Bool = false, secondsSinceForcedSleep: TimeInterval? = nil
    ) {
        self.isCaffeinated = isCaffeinated
        self.settingEnabled = settingEnabled
        self.idleSeconds = idleSeconds
        self.secondsSinceWake = secondsSinceWake
        self.thresholdSeconds = thresholdSeconds
        self.displayAsleep = displayAsleep
        self.holders = holders
        self.caffeinatePids = caffeinatePids
        self.remoteSessionActive = remoteSessionActive
        self.secondsSinceForcedSleep = secondsSinceForcedSleep
    }
}

/// Enforces "only Insomnia keeps the Mac awake" while decaffeinated.
///
/// Main-actor isolated: the timer, the menu and the decaffeinate hook all run on the main thread,
/// so the mutable state needs no lock.
@MainActor
public final class SleepEnforcer {
    // MARK: - Tunables

    /// Seconds between enforcement passes.
    public nonisolated static let passInterval: TimeInterval = 30
    /// Minimum seconds between forced sleeps, so a sleep-wake-sleep loop can't form.
    public nonisolated static let sleepCooldown: TimeInterval = 300
    /// Processes whose assertions (of any type) mean real work is happening; forced sleep waits for them.
    /// `coreaudiod` holds an assertion while audio plays with the display off, so forcing sleep would cut music or podcasts off.
    nonisolated static let exemptHolderNames: Set<String> = ["backupd", "softwareupdated", "coreaudiod"]

    // MARK: - Decision

    /// Phase 1 decision: which caffeinate processes to end. Pure: no I/O, no clock.
    public nonisolated static func decideSweep(
        isCaffeinated: Bool, settingEnabled: Bool, caffeinate: [ProcessIdentity]
    ) -> [EnforcerAction] {
        // Insomnia caffeinated or the setting off means the user wants nothing enforced.
        guard !isCaffeinated, settingEnabled, !caffeinate.isEmpty else { return [] }
        return [.terminate(caffeinate)]
    }

    /// Phase 2 decision: whether to put the Mac to sleep. Pure: no I/O, no clock.
    public nonisolated static func shouldSleep(_ input: EnforcerInput) -> Bool {
        guard !input.isCaffeinated, input.settingEnabled else { return false }

        // Only idle-blocking types that survive the sweep would still keep the Mac awake.
        let terminating = Set(input.caffeinatePids.map(\.pid))
        let blockers = input.holders.filter { $0.blocksIdleSleep && !terminating.contains($0.pid) }
        guard !blockers.isEmpty else { return false }

        // A display assertion (e.g. a video player) keeps the screen on; never interrupt it.
        guard input.displayAsleep else { return false }
        guard !input.remoteSessionActive else { return false }
        // The exemption looks at assertions of any type: backupd's BackgroundTask doesn't block sleep but is real work.
        guard !input.holders.contains(where: { exemptHolderNames.contains($0.processName) }) else { return false }
        guard let threshold = input.thresholdSeconds, let idle = input.idleSeconds else { return false }

        // Idle counts from the last wake so every wake gets a full threshold before we act.
        let effectiveIdle = min(idle, input.secondsSinceWake)
        guard effectiveIdle >= threshold else { return false }

        if let since = input.secondsSinceForcedSleep, since < sleepCooldown { return false }
        return true
    }

    /// Full decision for a snapshot: sweep first, then sleep if still warranted.
    public nonisolated static func decide(_ input: EnforcerInput) -> [EnforcerAction] {
        var actions = decideSweep(
            isCaffeinated: input.isCaffeinated, settingEnabled: input.settingEnabled, caffeinate: input.caffeinatePids
        )
        if shouldSleep(input) { actions.append(.sleepNow) }
        return actions
    }

    // MARK: - Dependencies

    private let powerManager: PowerAssertionManager
    private let configuration: InsomniaConfiguration
    private let processes: ProcessControlling
    private let idle: IdleStateProviding
    private let sleeper: SystemSleeping
    private let reader: ForeignAssertionReading
    private let remote: RemoteSessionDetecting
    private let wake: WakeTimeProviding
    private let monotonicNow: @Sendable () -> TimeInterval
    private let logger = Logger(subsystem: BuildEnvironment.bundleIdentifier, category: "SleepEnforcer")

    // MARK: - State

    /// Repeating pass timer.
    private var timer: Timer?
    /// Monotonic time of the last forced sleep, for the cooldown.
    private var lastForcedSleep: TimeInterval?

    // MARK: - Initialization

    /// Creates an enforcer. Defaults wire the real system implementations.
    public init(
        powerManager: PowerAssertionManager,
        configuration: InsomniaConfiguration,
        processes: ProcessControlling = SystemProcessController(),
        idle: IdleStateProviding = SystemIdleState(),
        sleeper: SystemSleeping = IOKitSystemSleeper(),
        reader: ForeignAssertionReading = IOKitForeignAssertionReader(),
        remote: RemoteSessionDetecting = SystemRemoteSessionDetector(),
        wake: WakeTimeProviding = WorkspaceWakeTracker.shared,
        monotonicNow: @escaping @Sendable () -> TimeInterval = { MonotonicClock.seconds() }
    ) {
        self.powerManager = powerManager
        self.configuration = configuration
        self.processes = processes
        self.idle = idle
        self.sleeper = sleeper
        self.reader = reader
        self.remote = remote
        self.wake = wake
        self.monotonicNow = monotonicNow
    }

    // MARK: - Lifecycle

    /// Starts the 30 s timer and runs a pass immediately.
    public func start() {
        ensureTimerRunning()
        enforceNow()
    }

    /// Stops the timer. Safe to call repeatedly.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ensures the repeating timer exists (same pattern as the schedule timer).
    private func ensureTimerRunning() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.passInterval, repeats: true) { [weak self] _ in
            // Timer's block is nonisolated; hop to the main actor where the enforcer lives.
            Task { @MainActor in self?.enforceNow() }
        }
    }

    // MARK: - Enforcement

    /// Runs one enforcement pass now.
    ///
    /// Two phases: the sweep first, then a fresh read of every safety input right before any sleep
    /// decision, so a snapshot taken before the sweep can't drive a stale forced sleep.
    public func enforceNow() {
        guard !powerManager.state.isActive, configuration.onlyInsomniaKeepsAwake else { return }

        // Phase 1: end other apps' caffeinate.
        let discovered = processes.caffeinateProcesses()
        for action in Self.decideSweep(isCaffeinated: false, settingEnabled: true, caffeinate: discovered) {
            if case .terminate(let targets) = action { terminate(targets) }
        }

        // Phase 2: re-read everything, and defer on any read that fails.
        guard !powerManager.state.isActive, configuration.onlyInsomniaKeepsAwake else { return }
        let holders: [ForeignAssertion]
        do {
            holders = try reader.readAssertions()
        } catch {
            logger.error("Skipping sleep check, could not read assertions: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let idleSeconds = idle.idleSeconds() else {
            logger.debug("Skipping sleep check: idle time unavailable")
            return
        }
        guard let threshold = idle.sleepThresholdSeconds() else {
            logger.debug("Skipping sleep check: sleep threshold unavailable or never")
            return
        }
        let now = monotonicNow()
        let input = EnforcerInput(
            isCaffeinated: powerManager.state.isActive,
            settingEnabled: configuration.onlyInsomniaKeepsAwake,
            idleSeconds: idleSeconds,
            secondsSinceWake: wake.secondsSinceWake(),
            thresholdSeconds: threshold,
            displayAsleep: idle.isDisplayAsleep(),
            holders: holders,
            caffeinatePids: discovered,
            remoteSessionActive: remote.isRemoteSessionActive(),
            secondsSinceForcedSleep: lastForcedSleep.map { now - $0 }
        )
        if Self.shouldSleep(input) { forceSleep(input: input) }
    }

    /// Reads other processes' assertions for the menu; failures are logged and yield an empty list.
    public func currentForeignHolders() -> [ForeignAssertion] {
        do {
            return try reader.readAssertions()
        } catch {
            logger.error("Could not read assertions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Sends SIGTERM to each process, logging the owning app for the record.
    private func terminate(_ targets: [ProcessIdentity]) {
        for target in targets {
            let owner = OwningAppResolver.resolve(
                pid: target.pid, parentOf: ProcessTable.parentPid(of:), nameOf: ProcessTable.displayName(of:)
            )
            do {
                if try processes.terminate(target) {
                    logger.notice("Terminated caffeinate pid \(target.pid) (owner: \(owner, privacy: .public))")
                } else {
                    // Gone, replaced, or no longer ours: nothing was signalled.
                    logger.debug("caffeinate pid \(target.pid) not signalled (already exited or changed)")
                }
            } catch {
                logger.error("Failed to terminate pid \(target.pid): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts the Mac to sleep and starts the cooldown.
    private func forceSleep(input: EnforcerInput) {
        let holderSummary = input.holders.filter(\.blocksIdleSleep)
            .map { "\($0.owningAppName):\($0.processName)" }.joined(separator: ", ")
        let idleText = input.idleSeconds.map { String(Int($0)) } ?? "unknown"
        do {
            try sleeper.sleepNow()
            lastForcedSleep = monotonicNow()
            logger.notice("Forced sleep after \(idleText)s idle; holders: \(holderSummary, privacy: .public)")
        } catch {
            logger.error("Forced sleep failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Real Implementations

/// Real process control: lists and SIGTERMs the user's own `/usr/bin/caffeinate` processes.
public final class SystemProcessController: ProcessControlling, @unchecked Sendable {
    /// Creates the controller.
    public init() {}

    /// The only executable we will ever signal. Matching the path (not just the name) stops a
    /// user-owned binary that happens to be called `caffeinate` from being a kill target.
    static let targetPath = "/usr/bin/caffeinate"

    /// Whether a pid is currently an `/usr/bin/caffeinate` owned (real uid) by this user, and not us.
    private func identityIfTarget(_ pid: Int32) -> ProcessIdentity? {
        guard pid != getpid(),
              ProcessTable.path(of: pid) == Self.targetPath,
              ProcessTable.realUid(of: pid) == getuid() else { return nil }
        return ProcessTable.identity(of: pid)
    }

    /// Our caffeinate processes with their start times.
    public func caffeinateProcesses() -> [ProcessIdentity] {
        ProcessTable.allPids().compactMap(identityIfTarget(_:))
    }

    /// SIGTERM only; revalidates path, owner and start time right before signalling to close the pid-reuse window.
    public func terminate(_ process: ProcessIdentity) throws -> Bool {
        guard let current = identityIfTarget(process.pid), current == process else { return false }
        if kill(process.pid, SIGTERM) == 0 { return true }
        if errno == ESRCH { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
    }
}

/// Real idle/display/threshold readings from CoreGraphics and IOKit.
public final class SystemIdleState: IdleStateProviding, @unchecked Sendable {
    /// Creates the provider.
    public init() {}

    /// Seconds since any input event in the combined session.
    public func idleSeconds() -> TimeInterval? {
        // kCGAnyInputEventType is ~0; CGEventType's init is failable so handle that without a force unwrap.
        guard let anyInput = CGEventType(rawValue: ~0) else { return nil }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// Whether every active display is asleep; false when the list can't be read (the safe answer).
    public func isDisplayAsleep() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success, count > 0 else { return false }
        return ids.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }

    /// max(system sleep, display sleep) for the active power source, in seconds.
    /// A zero timer is "never", so only a fully-zero pair means no forced sleep (nil).
    public func sleepThresholdSeconds() -> TimeInterval? {
        // The public IOKit API has no reader for the active sleep timers (IOPMCopyActivePMPreferences is
        // private), so read the same world-readable plist `pmset` edits.
        let url = URL(fileURLWithPath: Self.preferencesPath)
        let prefs: [String: Any]
        do {
            let data = try Data(contentsOf: url)
            guard let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                logger.error("Power preferences plist has an unexpected shape")
                return nil
            }
            prefs = parsed
        } catch {
            // Unknown threshold means no forced sleep, the safe direction.
            logger.error("Could not read power preferences: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return Self.threshold(from: prefs, sourceKey: Self.currentPowerSourceKey())
    }

    /// Pure threshold calculation from the preferences plist contents.
    ///
    /// - Parameters:
    ///   - prefs: Parsed `com.apple.PowerManagement.plist`.
    ///   - sourceKey: `AC Power` or `Battery Power`; nil (UPS / unknown source) yields nil.
    /// - Returns: max(system, display) sleep timer in seconds, or nil when either timer is missing
    ///   or both are zero ("never"), meaning no forced sleep.
    public nonisolated static func threshold(from prefs: [String: Any], sourceKey: String?) -> TimeInterval? {
        guard let sourceKey, let settings = prefs[sourceKey] as? [String: Any],
              let system = (settings["System Sleep Timer"] as? NSNumber)?.doubleValue,
              let display = (settings["Display Sleep Timer"] as? NSNumber)?.doubleValue else { return nil }
        // Whichever timer is set decides when macOS would sleep; both zero means it never will.
        let minutes = max(system, display)
        return minutes > 0 ? minutes * 60 : nil
    }

    /// Where macOS stores the sleep timers per power source.
    static let preferencesPath = "/Library/Preferences/com.apple.PowerManagement.plist"

    /// Logger for threshold read failures.
    private let logger = Logger(subsystem: BuildEnvironment.bundleIdentifier, category: "SystemIdleState")

    /// The preferences key for the power source currently supplying power; nil for UPS or unknown.
    static func currentPowerSourceKey() -> String? {
        // Copy-rule snapshot is retained here and released when it goes out of scope.
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              // The Get-rule string is owned by the snapshot, so it is unretained.
              let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return nil }
        if providing == kIOPSACPowerValue { return "AC Power" }
        if providing == kIOPSBatteryPowerValue { return "Battery Power" }
        return nil
    }
}

/// Real forced sleep through IOKit.
public final class IOKitSystemSleeper: SystemSleeping, @unchecked Sendable {
    /// Creates the sleeper.
    public init() {}

    /// Calls `IOPMSleepSystem` through the power-management service port.
    public func sleepNow() throws {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard port != 0 else { throw PowerAssertionError.creationFailed(ioReturn: Int32(kIOReturnNotFound)) }
        defer { IOServiceClose(port) }
        let result = IOPMSleepSystem(port)
        guard result == kIOReturnSuccess else { throw PowerAssertionError.creationFailed(ioReturn: result) }
    }
}

/// Real remote-session detection: SSH logins via utmpx, SSH without a terminal, Screen Sharing.
public final class SystemRemoteSessionDetector: RemoteSessionDetecting, @unchecked Sendable {
    /// Creates the detector.
    public init() {}

    /// True for an SSH login, an SSH connection without a PTY, or a running `screensharingd`.
    public func isRemoteSessionActive() -> Bool {
        if hasRemoteLogin() { return true }
        let pids = ProcessTable.allPids()
        return Self.hasRemoteProcess(pids: pids, nameOf: ProcessTable.name(of:), parentOf: ProcessTable.parentPid(of:))
    }

    /// Pure process-table check for remote sessions that utmpx can't see.
    ///
    /// - `sshd-session` runs once per SSH connection, with or without a PTY.
    /// - An `sshd` whose parent isn't launchd is a per-connection child (the launchd-owned one is the idle listener).
    /// - `screensharingd` is started on demand by launchd for each connection, so its presence means a live session.
    static func hasRemoteProcess(
        pids: [Int32], nameOf: (Int32) -> String?, parentOf: (Int32) -> Int32?
    ) -> Bool {
        for pid in pids {
            switch nameOf(pid) {
            case "sshd-session", "screensharingd":
                return true
            case "sshd":
                if let parent = parentOf(pid), parent != 1 { return true }
            default:
                continue
            }
        }
        return false
    }

    /// Scans utmpx for a USER_PROCESS entry whose `ut_host` is non-empty.
    private func hasRemoteLogin() -> Bool {
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            guard entry.pointee.ut_type == Int16(USER_PROCESS) else { continue }
            let host = withUnsafeBytes(of: entry.pointee.ut_host) { raw -> String in
                let bytes = raw.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
            if !host.isEmpty { return true }
        }
        return false
    }
}

/// Tracks `NSWorkspace.didWakeNotification` so idle can be measured from the last wake.
public final class WorkspaceWakeTracker: WakeTimeProviding, @unchecked Sendable {
    /// Shared tracker; observing once is enough.
    public static let shared = WorkspaceWakeTracker()

    /// Guards `lastWake`, which the notification and enforcer passes may touch from different threads.
    private let lock = NSLock()
    /// Monotonic time of the last wake. Launch counts as a wake so a fresh start also gets a full threshold.
    private var lastWake = MonotonicClock.seconds()
    /// Held so the observer can be removed.
    private var observer: NSObjectProtocol?

    /// Starts observing wake notifications.
    public init() {
        #if canImport(AppKit)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.recordWake()
        }
        #endif
    }

    deinit {
        #if canImport(AppKit)
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        #endif
    }

    /// Records a wake at the current monotonic time.
    func recordWake() {
        lock.lock()
        lastWake = MonotonicClock.seconds()
        lock.unlock()
    }

    /// Seconds since the last recorded wake (or launch).
    public func secondsSinceWake() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return MonotonicClock.seconds() - lastWake
    }
}
