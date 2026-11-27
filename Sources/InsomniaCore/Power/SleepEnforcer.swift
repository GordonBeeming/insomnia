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
    /// Pids of processes named exactly `caffeinate`, owned by the current user, excluding ours.
    func caffeinatePids() -> [Int32]
    /// Sends SIGTERM to `pid`.
    /// - Returns: `false` when the process was already gone (ESRCH).
    /// - Throws: For any failure other than ESRCH.
    func terminate(pid: Int32) throws -> Bool
}

/// Reports how idle the user and display are.
public protocol IdleStateProviding: Sendable {
    /// Seconds since the last keyboard/mouse/trackpad input, or nil if unknown.
    func idleSeconds() -> TimeInterval?
    /// Whether the main display is asleep.
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
    /// True when an SSH login or Screen Sharing session is active.
    func isRemoteSessionActive() -> Bool
}

/// Tells how long ago the Mac last woke.
public protocol WakeTimeProviding: Sendable {
    /// Seconds since the last wake (or since launch if it hasn't slept), never nil.
    func secondsSinceWake() -> TimeInterval
}

// MARK: - Decision Logic

/// One thing the enforcer should do in a pass.
public enum EnforcerAction: Equatable, Sendable {
    /// SIGTERM these caffeinate pids.
    case terminate([Int32])
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
    /// Other processes' assertions.
    public var holders: [ForeignAssertion]
    /// The current user's `caffeinate` pids.
    public var caffeinatePids: [Int32]
    /// Whether an SSH or Screen Sharing session is active.
    public var remoteSessionActive: Bool
    /// Seconds since the last forced sleep, nil if none this run.
    public var secondsSinceForcedSleep: TimeInterval?

    /// Creates an input record; every field is explicit so tests state their scenario.
    public init(
        isCaffeinated: Bool, settingEnabled: Bool, idleSeconds: TimeInterval?, secondsSinceWake: TimeInterval,
        thresholdSeconds: TimeInterval?, displayAsleep: Bool, holders: [ForeignAssertion],
        caffeinatePids: [Int32], remoteSessionActive: Bool = false, secondsSinceForcedSleep: TimeInterval? = nil
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
public final class SleepEnforcer: @unchecked Sendable {
    // MARK: - Tunables

    /// Seconds between enforcement passes.
    public static let passInterval: TimeInterval = 30
    /// Minimum seconds between forced sleeps, so a sleep-wake-sleep loop can't form.
    public static let sleepCooldown: TimeInterval = 300
    /// Processes whose assertions mean real work is happening; forced sleep waits for them.
    /// `coreaudiod` holds an assertion while audio plays with the display off, so forcing sleep would cut music or podcasts off.
    static let exemptHolderNames: Set<String> = ["backupd", "softwareupdated", "coreaudiod"]

    // MARK: - Decision

    /// Decides what to do for one pass. Pure: no I/O, no clock.
    ///
    /// - Parameter input: A snapshot of the system.
    /// - Returns: Actions in the order they should run.
    public static func decide(_ input: EnforcerInput) -> [EnforcerAction] {
        // Insomnia caffeinated or the setting off means the user wants nothing enforced.
        guard !input.isCaffeinated, input.settingEnabled else { return [] }

        var actions: [EnforcerAction] = []
        if !input.caffeinatePids.isEmpty {
            actions.append(.terminate(input.caffeinatePids))
        }

        // Holders that survive the terminate step are the ones that would still block idle sleep.
        let terminating = Set(input.caffeinatePids)
        let remaining = input.holders.filter { !terminating.contains($0.pid) }
        guard !remaining.isEmpty else { return actions }

        // A display assertion (e.g. a video player) keeps the screen on; never interrupt it.
        guard input.displayAsleep else { return actions }
        guard !input.remoteSessionActive else { return actions }
        guard !input.holders.contains(where: { exemptHolderNames.contains($0.processName) }) else { return actions }
        guard let threshold = input.thresholdSeconds, let idle = input.idleSeconds else { return actions }

        // Idle counts from the last wake so every wake gets a full threshold before we act.
        let effectiveIdle = min(idle, input.secondsSinceWake)
        guard effectiveIdle >= threshold else { return actions }

        if let since = input.secondsSinceForcedSleep, since < sleepCooldown { return actions }

        actions.append(.sleepNow)
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
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: BuildEnvironment.bundleIdentifier, category: "SleepEnforcer")

    // MARK: - State

    /// Repeating pass timer; main run loop only.
    private var timer: Timer?
    /// When we last forced a sleep, for the cooldown.
    private var lastForcedSleep: Date?
    /// Guards `lastForcedSleep` and `timer` against off-main callers (IPC thread).
    private let lock = NSLock()

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
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.powerManager = powerManager
        self.configuration = configuration
        self.processes = processes
        self.idle = idle
        self.sleeper = sleeper
        self.reader = reader
        self.remote = remote
        self.wake = wake
        self.now = now
    }

    // MARK: - Lifecycle

    /// Starts the 30 s timer and runs a pass immediately.
    public func start() {
        ensureTimerRunning()
        enforceNow()
    }

    /// Stops the timer. Safe to call repeatedly.
    public func stop() {
        lock.lock()
        timer?.invalidate()
        timer = nil
        lock.unlock()
    }

    /// Ensures the repeating timer exists (same pattern as the schedule timer).
    private func ensureTimerRunning() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.passInterval, repeats: true) { [weak self] _ in
            self?.enforceNow()
        }
    }

    // MARK: - Enforcement

    /// Runs one enforcement pass now.
    public func enforceNow() {
        // Cheap early exit so a caffeinated Mac or a disabled setting costs nothing per tick.
        guard !powerManager.state.isActive, configuration.onlyInsomniaKeepsAwake else { return }

        let holders = currentForeignHolders()
        let caffeinatePids = processes.caffeinatePids()
        lock.lock()
        let lastSleep = lastForcedSleep
        lock.unlock()

        let input = EnforcerInput(
            isCaffeinated: powerManager.state.isActive,
            settingEnabled: configuration.onlyInsomniaKeepsAwake,
            idleSeconds: idle.idleSeconds(),
            secondsSinceWake: wake.secondsSinceWake(),
            thresholdSeconds: idle.sleepThresholdSeconds(),
            displayAsleep: idle.isDisplayAsleep(),
            holders: holders,
            caffeinatePids: caffeinatePids,
            remoteSessionActive: remote.isRemoteSessionActive(),
            secondsSinceForcedSleep: lastSleep.map { now().timeIntervalSince($0) }
        )

        for action in Self.decide(input) {
            switch action {
            case .terminate(let pids):
                terminate(pids, holders: holders)
            case .sleepNow:
                forceSleep(input: input)
            }
        }
    }

    /// Reads other processes' assertions; failures are logged and yield an empty list.
    public func currentForeignHolders() -> [ForeignAssertion] {
        do {
            return try reader.readAssertions()
        } catch {
            logger.error("Could not read assertions: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Sends SIGTERM to each pid, logging the owning app for the record.
    private func terminate(_ pids: [Int32], holders: [ForeignAssertion]) {
        for pid in pids {
            let owner = holders.first { $0.pid == pid }?.owningAppName
                ?? OwningAppResolver.resolve(pid: pid, parentOf: ProcessTable.parentPid(of:), nameOf: ProcessTable.displayName(of:))
            do {
                if try processes.terminate(pid: pid) {
                    logger.notice("Terminated caffeinate pid \(pid) (owner: \(owner, privacy: .public))")
                } else {
                    // Already gone: another pass or the owner got there first.
                    logger.debug("caffeinate pid \(pid) already exited (ESRCH)")
                }
            } catch {
                logger.error("Failed to terminate pid \(pid): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Puts the Mac to sleep and starts the cooldown.
    private func forceSleep(input: EnforcerInput) {
        let holderSummary = input.holders.map { "\($0.owningAppName):\($0.processName)" }.joined(separator: ", ")
        let idleText = input.idleSeconds.map { String(Int($0)) } ?? "unknown"
        do {
            try sleeper.sleepNow()
            lock.lock()
            lastForcedSleep = now()
            lock.unlock()
            logger.notice("Forced sleep after \(idleText)s idle; holders: \(holderSummary, privacy: .public)")
        } catch {
            logger.error("Forced sleep failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Real Implementations

/// Real process control: lists and SIGTERMs the user's own `caffeinate` processes.
public final class SystemProcessController: ProcessControlling, @unchecked Sendable {
    /// Creates the controller.
    public init() {}

    /// The only executable name we will ever signal.
    private static let targetName = "caffeinate"

    /// Pids named exactly `caffeinate`, owned by this user, excluding our own pid.
    public func caffeinatePids() -> [Int32] {
        let me = getuid()
        let ownPid = getpid()
        return ProcessTable.allPids().filter { pid in
            pid != ownPid
                && ProcessTable.name(of: pid) == Self.targetName
                && ProcessTable.ownerUid(of: pid) == me
        }
    }

    /// SIGTERM only; re-checks name and owner right before signalling to narrow the pid-reuse window.
    public func terminate(pid: Int32) throws -> Bool {
        guard pid != getpid(),
              ProcessTable.name(of: pid) == Self.targetName,
              ProcessTable.ownerUid(of: pid) == getuid() else {
            // Not (or no longer) a caffeinate of ours: treat as gone rather than risk another process.
            return false
        }
        if kill(pid, SIGTERM) == 0 { return true }
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

    /// Whether the main display is asleep.
    public func isDisplayAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
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
        guard let settings = prefs[Self.currentPowerSourceKey()] as? [String: Any] else { return nil }
        let systemMinutes = (settings["System Sleep Timer"] as? NSNumber)?.doubleValue ?? 0
        let displayMinutes = (settings["Display Sleep Timer"] as? NSNumber)?.doubleValue ?? 0
        // Whichever timer is set decides when macOS would sleep; both zero means it never will.
        let minutes = max(systemMinutes, displayMinutes)
        return minutes > 0 ? minutes * 60 : nil
    }

    /// Where macOS stores the sleep timers per power source.
    static let preferencesPath = "/Library/Preferences/com.apple.PowerManagement.plist"

    /// Logger for threshold read failures.
    private let logger = Logger(subsystem: BuildEnvironment.bundleIdentifier, category: "SystemIdleState")

    /// The preferences key for the power source currently supplying power.
    static func currentPowerSourceKey() -> String {
        let providing = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?
        return providing == kIOPSBatteryPowerValue ? "Battery Power" : "AC Power"
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

/// Real remote-session detection: SSH logins via utmpx, Screen Sharing via its daemon.
public final class SystemRemoteSessionDetector: RemoteSessionDetecting, @unchecked Sendable {
    /// Creates the detector.
    public init() {}

    /// True for an SSH login (utmpx user process with a host) or a running `screensharingd`.
    public func isRemoteSessionActive() -> Bool {
        hasRemoteLogin() || ProcessTable.allPids().contains { ProcessTable.name(of: $0) == "screensharingd" }
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

    /// Guards `lastWake`, which the notification (main) and enforcer passes may touch.
    private let lock = NSLock()
    /// Launch counts as a wake so a fresh start also gets a full threshold.
    private var lastWake = Date()
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

    /// Records a wake at the current time.
    func recordWake() {
        lock.lock()
        lastWake = Date()
        lock.unlock()
    }

    /// Seconds since the last recorded wake (or launch).
    public func secondsSinceWake() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastWake)
    }
}
