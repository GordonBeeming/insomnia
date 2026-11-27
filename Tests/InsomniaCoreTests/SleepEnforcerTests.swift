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
    var pids: [Int32] = []
    var terminated: [Int32] = []
    /// Pids that report as already gone (ESRCH).
    var gone: Set<Int32> = []
    func caffeinatePids() -> [Int32] { pids }
    func terminate(pid: Int32) throws -> Bool {
        terminated.append(pid)
        return !gone.contains(pid)
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
    func readAssertions() throws -> [ForeignAssertion] { assertions }
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
    var date = Date(timeIntervalSince1970: 1_000_000)
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
        input.caffeinatePids = [1]
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testSettingOffIsNoOp() {
        var input = sleepyInput()
        input.settingEnabled = false
        input.caffeinatePids = [1]
        XCTAssertEqual(SleepEnforcer.decide(input), [])
    }

    func testDecaffeinatedTerminatesCaffeinatePids() {
        var input = sleepyInput()
        input.holders = []
        input.caffeinatePids = [11, 12]
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate([11, 12])])
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
        input.caffeinatePids = [11]
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate([11])])
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
        input.caffeinatePids = [11]
        XCTAssertEqual(SleepEnforcer.decide(input), [.terminate([11])])
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
            reader: reader, remote: remote, wake: wake, now: { clock.date }
        )
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPassTerminatesCaffeinateWhenDecaffeinated() {
        processes.pids = [42]
        enforcer.enforceNow()
        XCTAssertEqual(processes.terminated, [42])
        XCTAssertEqual(sleeper.count, 0)
    }

    func testAlreadyGoneProcessIsIgnored() {
        processes.pids = [42]
        processes.gone = [42]
        enforcer.enforceNow()
        XCTAssertEqual(processes.terminated, [42])
    }

    func testCaffeinatedMeansNoTerminate() throws {
        processes.pids = [42]
        try power.caffeinate()
        enforcer.enforceNow()
        XCTAssertTrue(processes.terminated.isEmpty)
    }

    func testOnDecaffeinatedTriggersPass() throws {
        processes.pids = [42]
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
        clock.date.addTimeInterval(60)
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 1, "cooldown should block the second sleep")
        clock.date.addTimeInterval(300)
        enforcer.enforceNow()
        XCTAssertEqual(sleeper.count, 2)
    }

    func testSettingOffSkipsEverything() {
        config.onlyInsomniaKeepsAwake = false
        processes.pids = [42]
        reader.assertions = [holder()]
        idle.idle = 1200
        idle.displayAsleep = true
        enforcer.enforceNow()
        XCTAssertTrue(processes.terminated.isEmpty)
        XCTAssertEqual(sleeper.count, 0)
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
