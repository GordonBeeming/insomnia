// SleepEnforcerTests.swift — InsomniaCoreTests
//
// Covers the SleepEnforcer decision table, the enforcer's orchestration through
// mock protocols (no real process is signalled, the Mac is never slept), the
// owning-app resolver, the menu summary, and the setting's default/persistence.

import XCTest
@testable import InsomniaCore

// MARK: - Mocks

/// Records terminations instead of signalling anything.
final class MockProcessController: ProcessControlling, @unchecked Sendable {
    var pids: [ProcessIdentity] = []
    var terminated: [Int32] = []
    /// Pids that report as already gone (ESRCH).
    var gone: Set<Int32> = []
    /// Runs during the sweep, to simulate the world changing while processes are being ended.
    var onTerminate: (() -> Void)?
    func caffeinateProcesses() -> [ProcessIdentity] { pids }
    func terminate(_ process: ProcessIdentity) throws -> Bool {
        terminated.append(process.pid)
        onTerminate?()
        return !gone.contains(process.pid)
    }
}

/// Fixed idle readings.
final class MockIdleState: IdleStateProviding, @unchecked Sendable {
        var idle: TimeInterval? = 0
    var displayAsleep = false
    var threshold: TimeInterval? = 600
    func idleSeconds() -> TimeInterval? { idle }
    func isDisplayAsleep() -> Bool { displayAsleep }
    func sleepThresholdSeconds() -> TimeInterval? { threshold }
}

/// Counts sleep requests; never touches IOKit.
final class MockSleeper: SystemSleeping, @unchecked Sendable {
    var count = 0
    func sleepNow() throws { count += 1 }
}

/// Fixed assertion list.
final class MockReader: ForeignAssertionReading, @unchecked Sendable {
    var assertions: [ForeignAssertion] = []
    /// When set, reads throw it (a failed safety read must defer sleep).
    var error: Error?
    func readAssertions() throws -> [ForeignAssertion] {
        if let error { throw error }
        return assertions
    }
}

/// Fixed remote-session answer.
final class MockRemote: RemoteSessionDetecting, @unchecked Sendable {
    var active = false
    func isRemoteSessionActive() -> Bool { active }
}

/// Fixed time since wake.
final class MockWake: WakeTimeProviding, @unchecked Sendable {
    var seconds: TimeInterval = 100_000
    func secondsSinceWake() -> TimeInterval { seconds }
}

/// Mutable clock for cooldown tests.
final class MockClock: @unchecked Sendable {
    var seconds: TimeInterval = 1_000_000
}

// MARK: - Helpers

/// Fixed suite names: one stable plist per test class instead of a new file per test run.
/// cfprefsd writes the plist back asynchronously, so deleting files is racy; reusing one name is not.
let orchestrationSuiteName = "com.insomnia.tests.SleepEnforcer"
let settingSuiteName = "com.insomnia.tests.OnlyInsomniaSetting"

/// Returns a clean defaults suite: any state from a previous test or run is removed first.
func freshSuite(_ name: String) -> UserDefaults {
    UserDefaults.standard.removePersistentDomain(forName: name)
    return UserDefaults(suiteName: name) ?? .standard
}

/// Builds process identities with fixed start times for the given pids.
private func ids(_ pids: Int32...) -> [ProcessIdentity] {
    pids.map { ProcessIdentity(pid: $0, startSeconds: 1, startMicroseconds: 2) }
}

private func holder(_ pid: Int32 = 100, process: String = "claude", app: String = "claude") -> ForeignAssertion {
    ForeignAssertion(pid: pid, processName: process, owningAppName: app,
                     type: "PreventUserIdleSystemSleep", name: "test")
}

/// A scenario where a sleep is warranted; tests change one field at a time.
private func sleepyInput() -> EnforcerInput {
    EnforcerInput(isCaffeinated: false, settingEnabled: true, idleSeconds: 1200, secondsSinceWake: 5000,
                  thresholdSeconds: 600, displayAsleep: true, holders: [holder()], caffeinatePids: [])
}

// MARK: - Decision Table

final class SleepEnforcerDecisionTests: XCTestCase {
    func testCaffeinatedIsNoOp() {
        var input = sleepyInput()
        input.isCaffeinated = true
        input.caffeinatePids = ids(1)
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testSettingOffIsNoOp() {
        var input = sleepyInput()
        input.settingEnabled = false
        input.caffeinatePids = ids(1)
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testDecaffeinatedTerminatesCaffeinatePids() {
        var input = sleepyInput()
        input.holders = []
        input.caffeinatePids = ids(11, 12)
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate(ids(11, 12))])
    }

    func testIdleBelowThresholdDoesNotSleep() {
        var input = sleepyInput()
        input.idleSeconds = 599
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testDisplayAwakeDoesNotSleep() {
        var input = sleepyInput()
        input.displayAsleep = false
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testIdlePastThresholdDisplayAsleepHolderPresentSleeps() {
        XCTAssertEqual(SleepEnforcer.decide(sleepyInput()), [.sleepNow])
    }

    func testNoHolderDoesNotSleep() {
        var input = sleepyInput()
        input.holders = []
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testOnlyTerminatedHoldersDoNotSleepThisPass() {
        var input = sleepyInput()
        input.holders = [holder(11, process: "caffeinate")]
        input.caffeinatePids = ids(11)
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate(ids(11))])
    }

    func testThresholdNeverDoesNotSleep() {
        var input = sleepyInput()
        input.thresholdSeconds = nil
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testBackupdHolderDefersSleep() {
        var input = sleepyInput()
        input.holders = [holder(), holder(7, process: "backupd", app: "backupd")]
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testSoftwareupdatedHolderDefersSleep() {
        var input = sleepyInput()
        input.holders = [holder(), holder(8, process: "softwareupdated", app: "softwareupdated")]
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testCoreaudiodHolderDefersSleepButTerminateStillRuns() {
        var input = sleepyInput()
        input.holders = [holder(), holder(9, process: "coreaudiod", app: "coreaudiod"), holder(11, process: "caffeinate")]
        input.caffeinatePids = ids(11)
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate(ids(11))])
    }

    func testCooldownBlocksSecondSleep() {
        var input = sleepyInput()
        input.secondsSinceForcedSleep = 120
        XCTAssertEqual(SleepEnforcer.decide(input), [])
        input.secondsSinceForcedSleep = 301
        XCTAssertEqual(SleepEnforcer.decide(input), [.sleepNow])
    }

    func testIdleCountsFromLastWake() {
        var input = sleepyInput()
        input.secondsSinceWake = 30
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testRemoteSessionDefersSleep() {
        var input = sleepyInput()
        input.remoteSessionActive = true
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testUnknownIdleDoesNotSleep() {
        var input = sleepyInput()
        input.idleSeconds = nil
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }
}

// MARK: - Orchestration

@MainActor
final class SleepEnforcerOrchestrationTests: XCTestCase {
    private var power: PowerAssertionManager!
    private var config: InsomniaConfiguration!
    private var processes: MockProcessController!
    private var idle: MockIdleState!
    private var sleeper: MockSleeper!
    private var reader: MockReader!
    private var remote: MockRemote!
    private var wake: MockWake!
    private var clock: MockClock!
    private var enforcer: SleepEnforcer!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = orchestrationSuiteName
        config = InsomniaConfiguration(defaults: freshSuite(suiteName))
        power = PowerAssertionManager(provider: MockPowerAssertionProvider())
        processes = MockProcessController()
        idle = MockIdleState()
        sleeper = MockSleeper()
        reader = MockReader()
        remote = MockRemote()
        wake = MockWake()
        clock = MockClock()
        let clock = self.clock!
        enforcer = SleepEnforcer(
            powerManager: power, configuration: config, processes: processes, idle: idle, sleeper: sleeper,
            reader: reader, remote: remote, wake: wake, monotonicNow: { clock.seconds }
        )
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPassTerminatesCaffeinateWhenDecaffeinated() {
        processes.pids = ids(42)
        enforcer.enforceNow()
        XCTAssertEqual(processes.terminated, [42])
        XCTAssertEqual(sleeper.count, 0)
    }

    func testAlreadyGoneProcessIsIgnored() {
        processes.pids = ids(42)
        processes.gone = [42]
        enforcer.enforceNow()
        XCTAssertEqual(processes.terminated, [42])
    }

    func testCaffeinatedMeansNoTerminate() throws {
        processes.pids = ids(42)
        try power.caffeinate()
        enforcer.enforceNow()
        XCTAssertTrue(processes.terminated.isEmpty)
    }

    func testOnDecaffeinatedTriggersPass() throws {
        processes.pids = ids(42)
        power.onDecaffeinated = { [enforcer] in enforcer?.enforceNow() }
        try power.caffeinate()
        try power.decaffeinate()
        XCTAssertEqual(processes.terminated, [42])
    }

    func testForcedSleepThenCooldown() {
        reader.assertions = [holder()]
        idle.idle = 1200
        idle.displayAsleep = true
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 1)
        clock.seconds += (60)
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 1, "cooldown should block the second sleep")
        clock.seconds += (300)
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 2)
    }

    func testSettingOffSkipsEverything() {
        config.onlyInsomniaKeepsAwake = false
        processes.pids = ids(42)
        reader.assertions = [holder()]
        idle.idle = 1200
        idle.displayAsleep = true
        enforcer.enforceNow()
        XCTAssertTrue(processes.terminated.isEmpty)
        XCTAssertEqual(sleeper.count, 0)
    }

    func testIdleChangingAfterSweepPreventsSleep() {
        // Idle is past the threshold before the sweep; the user returns while caffeinate is being ended.
        // The phase-2 read must see the new idle value and not sleep.
        reader.assertions = [holder()]
        idle.displayAsleep = true
        idle.idle = 1200
        processes.pids = ids(42)
        let idle = self.idle!
        processes.onTerminate = { idle.idle = 0 }
        enforcer.enforceNow()
        XCTAssertEqual(processes.terminated, [42])
        XCTAssertEqual(sleeper.count, 0)
    }

    func testFailedAssertionReadDefersSleep() {
        struct ReadFailure: Error {}
        reader.error = ReadFailure()
        idle.idle = 1200
        idle.displayAsleep = true
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 0)
    }

    func testUnknownIdleOrThresholdDefersSleep() {
        reader.assertions = [holder()]
        idle.displayAsleep = true
        idle.idle = nil
        enforcer.enforceNow()
        idle.idle = 1200
        idle.threshold = nil
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 0)
    }

    func testBackgroundTaskFromBackupdExemptsSleep() {
        // backupd's BackgroundTask doesn't block idle sleep but still signals real work.
        let backup = ForeignAssertion(pid: 7, processName: "backupd", owningAppName: "backupd",
                                      type: "BackgroundTask", name: "backup")
        reader.assertions = [holder(), backup]
        idle.idle = 1200
        idle.displayAsleep = true
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 0)
    }

    func testEnablingSettingRunsImmediatePass() {
        config.onlyInsomniaKeepsAwake = false
        processes.pids = ids(42)
        config.onEnforcementEnabled = { [enforcer] in
            MainActor.assumeIsolated { enforcer?.enforceNow() }
        }
        config.onlyInsomniaKeepsAwake = true
        XCTAssertEqual(processes.terminated, [42])
    }
}

// MARK: - Resolver, Summary, Configuration

final class ForeignAssertionTests: XCTestCase {
    func testOwningAppSkipsCaffeinateAndShell() {
        let parents: [Int32: Int32] = [56038: 500, 500: 400, 400: 1]
        let names: [Int32: String] = [56038: "caffeinate", 500: "zsh", 400: "claude"]
        let app = OwningAppResolver.resolve(pid: 56038, parentOf: { parents[$0] }, nameOf: { names[$0] })
        XCTAssertEqual(app, "claude")
    }

    func testOwningAppFallsBackToOwnName() {
        let app = OwningAppResolver.resolve(pid: 9, parentOf: { _ in nil }, nameOf: { $0 == 9 ? "caffeinate" : nil })
        XCTAssertEqual(app, "caffeinate")
    }

    func testSummaryGroupsByAppAndCaps() {
        let holders = (0..<7).map { holder(Int32($0), process: "caffeinate", app: "app\($0)") }
            + [holder(99, process: "caffeinate", app: "app0")]
        let rows = ForeignHolderSummary.rows(for: holders, limit: 5)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0], "app0 \u{2014} caffeinate (prevent idle sleep)")
        XCTAssertEqual(rows[5], "+2 more")
    }

    func testPowerdIsSystemPolicyAndAppsAreNot() {
        XCTAssertTrue(holder(5, process: "powerd", app: "powerd").isSystemPolicy)
        XCTAssertFalse(holder(6, process: "caffeinate", app: "claude").isSystemPolicy)
    }

    func testReaderParseKeepsAllTypesAndDropsPowerdAndSelf() {
        func entry(_ type: String, _ name: String) -> [String: Any] {
            ["AssertType": type, "AssertName": name]
        }
        let table: [NSNumber: [[String: Any]]] = [
            10: [entry("PreventUserIdleSystemSleep", "caffeinate command-line tool")],
            20: [entry("BackgroundTask", "backup")],
            30: [entry("PreventUserIdleSystemSleep", "Powerd - Prevent sleep while display is on")],
            40: [entry("PreventUserIdleSystemSleep", "ours")],
        ]
        let names: [Int32: String] = [10: "caffeinate", 20: "backupd", 30: "powerd", 40: "Insomnia", 99: "claude"]
        let parents: [Int32: Int32] = [10: 99]
        let parsed = IOKitForeignAssertionReader.parse(
            table, ownPid: 40, nameOf: { names[$0] }, parentOf: { parents[$0] }, displayNameOf: { names[$0] }
        )
        // Sorted by owning app name: "backupd" < "claude".
        XCTAssertEqual(parsed.map(\.pid), [20, 10])
        let caffeinate = parsed.first { $0.pid == 10 }
        XCTAssertEqual(caffeinate?.owningAppName, "claude")
        XCTAssertEqual(caffeinate?.blocksIdleSleep, true)
        XCTAssertEqual(parsed.first { $0.pid == 20 }?.blocksIdleSleep, false)
        XCTAssertFalse(parsed.contains { $0.pid == 30 || $0.pid == 40 })
    }

    func testParseFiltersPowerdNamedInTableWhenProcNameUnavailable() {
        // A notarized app can't proc_name root daemons, but the assertion dict names the holder.
        let table: [NSNumber: [[String: Any]]] = [
            571: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "Powerd - Prevent sleep while display is on",
                   "Process Name": "powerd"]],
        ]
        let parsed = IOKitForeignAssertionReader.parse(
            table, ownPid: 1, nameOf: { _ in nil }, parentOf: { _ in nil }, displayNameOf: { _ in nil }
        )
        XCTAssertTrue(parsed.isEmpty)
    }

    func testParseUsesTableNameAndOnBehalfOfApp() {
        let assertionStart = Date(timeIntervalSince1970: 2_000_000)
        let table: [NSNumber: [[String: Any]]] = [
            634: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "ClaudeBar", "Process Name": "runningboardd",
                   "AssertionOnBehalfOfPID": 14916, "AssertStartWhen": assertionStart]],
            700: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "x", "Process Name": "sharingd"]],
        ]
        let names: [Int32: String] = [14916: "ClaudeBar"]
        let parsed = IOKitForeignAssertionReader.parse(
            table, ownPid: 1, nameOf: { names[$0] }, parentOf: { _ in nil }, displayNameOf: { names[$0] },
            startDateOf: { _ in assertionStart.addingTimeInterval(-60) }
        )
        let board = parsed.first { $0.pid == 634 }
        XCTAssertEqual(board?.processName, "runningboardd")
        XCTAssertEqual(board?.owningAppName, "ClaudeBar")
        // No name lookup works for pid 700, so the table's name is used rather than "pid 700".
        XCTAssertEqual(parsed.first { $0.pid == 700 }?.owningAppName, "sharingd")
    }

    /// Parses one runningboardd assertion made on behalf of pid 14916, given the beneficiary's start time and the assertion's.
    private func parseOnBehalf(assertionStart: Date?, processStart: Date?) -> ForeignAssertion? {
        var entry: [String: Any] = ["AssertType": "PreventUserIdleSystemSleep", "AssertName": "x",
                                    "Process Name": "runningboardd", "AssertionOnBehalfOfPID": 14916]
        if let assertionStart { entry["AssertStartWhen"] = assertionStart }
        let names: [Int32: String] = [14916: "ClaudeBar"]
        return IOKitForeignAssertionReader.parse(
            [634: [entry]], ownPid: 1, nameOf: { names[$0] }, parentOf: { _ in nil }, displayNameOf: { names[$0] },
            startDateOf: { _ in processStart }
        ).first
    }

    func testOnBehalfAttributionRequiresBeneficiaryStartedBeforeAssertion() {
        let assertion = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(parseOnBehalf(assertionStart: assertion, processStart: assertion.addingTimeInterval(-5))?.owningAppName,
                       "ClaudeBar", "beneficiary predates the assertion: trusted")
        // The pid was reused after the assertion: the name would belong to an unrelated process.
        XCTAssertEqual(parseOnBehalf(assertionStart: assertion, processStart: assertion.addingTimeInterval(5))?.owningAppName,
                       "runningboardd")
    }

    func testOnBehalfAttributionFallsBackWhenATimestampIsMissing() {
        let assertion = Date(timeIntervalSince1970: 2_000_000)
        XCTAssertEqual(parseOnBehalf(assertionStart: nil, processStart: assertion)?.owningAppName, "runningboardd")
        XCTAssertEqual(parseOnBehalf(assertionStart: assertion, processStart: nil)?.owningAppName, "runningboardd")
    }

    func testTableOnlyExemptHoldersEachPreventSleepAndStayOutOfMenu() {
        // proc_name can't name root daemons in the notarized app, so only the table's "Process Name" identifies them.
        let table: [NSNumber: [[String: Any]]] = [
            100: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "claude", "Process Name": "claude"]],
            200: [["AssertType": "PreventUserIdleSystemSleep", "AssertName": "audio", "Process Name": "coreaudiod"]],
            300: [["AssertType": "BackgroundTask", "AssertName": "backup", "Process Name": "backupd"]],
        ]
        let parsed = IOKitForeignAssertionReader.parse(
            table, ownPid: 1, nameOf: { _ in nil }, parentOf: { _ in nil }, displayNameOf: { _ in nil }
        )
        func input(_ holders: [ForeignAssertion]) -> EnforcerInput {
            EnforcerInput(isCaffeinated: false, settingEnabled: true, idleSeconds: 1200, secondsSinceWake: 5000,
                          thresholdSeconds: 600, displayAsleep: true, holders: holders, caffeinatePids: [])
        }
        let claude = parsed.filter { $0.pid == 100 }
        XCTAssertTrue(SleepEnforcer.shouldSleep(input(claude)), "control: a lone blocker does sleep")
        for exemptPid in [Int32(200), 300] {
            let withExempt = claude + parsed.filter { $0.pid == exemptPid }
            XCTAssertFalse(SleepEnforcer.shouldSleep(input(withExempt)), "pid \(exemptPid) should prevent sleep")
            XCTAssertEqual(SleepEnforcer.decide(input(withExempt)), [])
        }
        let rows = ForeignHolderSummary.rows(for: parsed)
        XCTAssertFalse(rows.contains { $0.contains("backupd") }, "BackgroundTask stays out of the menu")
    }

    func testRowsCollapseWhenProcessIsTheApp() {
        let selfNamed = ForeignAssertion(pid: 1, processName: "sharingd", owningAppName: "sharingd",
                                         type: "PreventUserIdleSystemSleep", name: "")
        let onBehalf = ForeignAssertion(pid: 2, processName: "runningboardd", owningAppName: "ClaudeBar",
                                        type: "PreventUserIdleSystemSleep", name: "")
        XCTAssertEqual(ForeignHolderSummary.rows(for: [selfNamed, onBehalf]),
                       ["sharingd (prevent idle sleep)", "ClaudeBar \u{2014} runningboardd (prevent idle sleep)"])
        XCTAssertEqual(ForeignHolderSummary.groupCount(for: [selfNamed, onBehalf]), 2)
    }

    func testSummaryHidesNonBlockingTypes() {
        let task = ForeignAssertion(pid: 7, processName: "backupd", owningAppName: "backupd",
                                    type: "BackgroundTask", name: "backup")
        XCTAssertTrue(ForeignHolderSummary.rows(for: [task]).isEmpty)
    }

    func testRemoteProcessDetection() {
        let names: [Int32: String] = [1: "launchd", 2: "sshd", 3: "sshd", 4: "sshd-session", 5: "zsh", 6: "screensharingd"]
        let parents: [Int32: Int32] = [2: 1, 3: 2, 4: 3, 5: 4, 6: 1]
        func detect(_ pids: [Int32]) -> Bool {
            SystemRemoteSessionDetector.hasRemoteProcess(pids: pids, nameOf: { names[$0] }, parentOf: { parents[$0] })
        }
        XCTAssertFalse(detect([1, 2]), "launchd-owned sshd is just the listener")
        XCTAssertTrue(detect([3]), "sshd child of sshd is a connection")
        XCTAssertTrue(detect([4]), "sshd-session means an SSH connection, with or without a PTY")
        XCTAssertTrue(detect([6]), "screensharingd runs per connection")
        XCTAssertFalse(detect([5]))
    }

    func testSummaryEmptyForNoHolders() {
        XCTAssertTrue(ForeignHolderSummary.rows(for: []).isEmpty)
    }
}

final class OnlyInsomniaSettingTests: XCTestCase {
    func testDefaultsToTrueWhenKeyMissing() {
        let defaults = freshSuite(settingSuiteName)
        defer { UserDefaults.standard.removePersistentDomain(forName: settingSuiteName) }
        XCTAssertTrue(InsomniaConfiguration(defaults: defaults).onlyInsomniaKeepsAwake)
    }

    func testPersistsFalse() {
        let defaults = freshSuite(settingSuiteName)
        defer { UserDefaults.standard.removePersistentDomain(forName: settingSuiteName) }
        let first = InsomniaConfiguration(defaults: defaults)
        first.onlyInsomniaKeepsAwake = false
        XCTAssertFalse(InsomniaConfiguration(defaults: defaults).onlyInsomniaKeepsAwake)
    }
}

// MARK: - Threshold

final class SleepThresholdTests: XCTestCase {
    private let prefs: [String: Any] = [
        "AC Power": ["System Sleep Timer": 1, "Display Sleep Timer": 30],
        "Battery Power": ["System Sleep Timer": 1, "Display Sleep Timer": 10],
        "UPS Power": ["System Sleep Timer": 5, "Display Sleep Timer": 5],
    ]

    func testACUsesLargerTimer() {
        XCTAssertEqual(SystemIdleState.threshold(from: prefs, sourceKey: "AC Power"), 1800)
    }

    func testBatteryUsesLargerTimer() {
        XCTAssertEqual(SystemIdleState.threshold(from: prefs, sourceKey: "Battery Power"), 600)
    }

    func testMissingKeyIsNil() {
        let partial: [String: Any] = ["AC Power": ["System Sleep Timer": 1]]
        XCTAssertNil(SystemIdleState.threshold(from: partial, sourceKey: "AC Power"))
    }

    func testBothZeroIsNil() {
        let never: [String: Any] = ["AC Power": ["System Sleep Timer": 0, "Display Sleep Timer": 0]]
        XCTAssertNil(SystemIdleState.threshold(from: never, sourceKey: "AC Power"))
    }

    func testUPSOrUnknownSourceIsNil() {
        XCTAssertNil(SystemIdleState.threshold(from: prefs, sourceKey: nil))
        XCTAssertNil(SystemIdleState.threshold(from: prefs, sourceKey: "Elsewhere"))
    }
}
