// CaffeinationSchedulerTests.swift — InsomniaCoreTests
//
// Tests for CaffeinationScheduler orchestration using a mocked
// PowerAssertionManager. Verifies timed caffeination, app-watching,
// schedule rule management, and cancelAll behavior.

import XCTest
@testable import InsomniaCore

/// Tests for the CaffeinationScheduler orchestrator.
final class CaffeinationSchedulerTests: XCTestCase {
    /// Mock provider for the power manager.
    var mockProvider: MockPowerAssertionProvider!
    /// Power manager using the mock provider.
    var powerManager: PowerAssertionManager!
    /// The scheduler under test.
    var scheduler: CaffeinationScheduler!

    /// Sets up fresh test instances before each test.
    override func setUp() {
        super.setUp()
        // Create mock provider and inject into power manager
        mockProvider = MockPowerAssertionProvider()
        powerManager = PowerAssertionManager(provider: mockProvider)
        scheduler = CaffeinationScheduler(powerManager: powerManager)
    }

    /// Cleans up test resources.
    override func tearDown() {
        scheduler = nil
        powerManager = nil
        mockProvider = nil
        super.tearDown()
    }

    // MARK: - Initial State

    /// Verifies the scheduler starts in decaffeinated state with no rules.
    func testInitialState() {
        // Scheduler should start with no rules and decaffeinated
        XCTAssertTrue(scheduler.scheduleRules.isEmpty)
        XCTAssertEqual(scheduler.powerManager.state, .decaffeinated)
    }

    // MARK: - Timed Caffeination

    /// Tests starting timed caffeination with a preset duration.
    func testStartTimedWithPreset() throws {
        // Start 15-minute caffeination
        try scheduler.startTimed(.fifteenMinutes)
        // Power manager should be in timed state
        if case .caffeinatedUntil = scheduler.powerManager.state {
            // Expected state
        } else {
            XCTFail("Expected caffeinatedUntil state")
        }
        // Mock should have created one assertion
        XCTAssertEqual(mockProvider.createCallCount, 1)
    }

    /// Tests starting timed caffeination with a custom duration.
    func testStartTimedWithCustomDuration() throws {
        // Start 45-minute caffeination
        try scheduler.startTimed(.custom(2700))
        // Verify the state includes an end date approximately 45 minutes from now
        if case .caffeinatedUntil(let date) = scheduler.powerManager.state {
            let expected = Date().addingTimeInterval(2700)
            XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 2)
        } else {
            XCTFail("Expected caffeinatedUntil state")
        }
    }

    // MARK: - Until Date

    /// Tests caffeination until a specific date.
    func testStartUntilDate() throws {
        // Set a target 1 hour from now
        let target = Date().addingTimeInterval(3600)
        try scheduler.startUntil(target)
        // Verify the state
        XCTAssertEqual(scheduler.powerManager.state, .caffeinatedUntil(target))
    }

    // MARK: - App Watching

    /// Tests starting app-watching caffeination.
    func testStartWhileAppRunning() throws {
        // Start watching Safari
        try scheduler.startWhileAppRunning(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        // Verify the state
        if case .caffeinatedWhileRunning(let bundleID, let name) = scheduler.powerManager.state {
            XCTAssertEqual(bundleID, "com.apple.Safari")
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected caffeinatedWhileRunning state")
        }
    }

    /// Tests that app name defaults to bundle ID suffix when not provided.
    func testStartWhileAppRunningDefaultName() throws {
        // Start watching without explicit app name
        try scheduler.startWhileAppRunning(bundleIdentifier: "com.example.MyApp")
        // Verify the display name was derived from the bundle ID
        if case .caffeinatedWhileRunning(_, let name) = scheduler.powerManager.state {
            XCTAssertEqual(name, "MyApp")
        } else {
            XCTFail("Expected caffeinatedWhileRunning state")
        }
    }

    // MARK: - Cancel All

    /// Tests that cancelAll releases assertions and resets state.
    func testCancelAll() throws {
        // First start caffeination
        try scheduler.startTimed(.oneHour)
        XCTAssertTrue(scheduler.powerManager.state.isActive)
        // Cancel everything
        try scheduler.cancelAll()
        // Should be decaffeinated
        XCTAssertEqual(scheduler.powerManager.state, .decaffeinated)
        XCTAssertEqual(mockProvider.releaseCallCount, 1)
    }

    /// Tests that cancelAll is safe when already decaffeinated.
    func testCancelAllWhenAlreadyDecaffeinated() throws {
        // Should not throw
        try scheduler.cancelAll()
        XCTAssertEqual(scheduler.powerManager.state, .decaffeinated)
    }

    // MARK: - Schedule Rules

    /// Tests adding a schedule rule.
    func testAddScheduleRule() {
        // Create and add a rule
        let rule = makeTestRule()
        scheduler.addScheduleRule(rule)
        // Should be in the rules list
        XCTAssertEqual(scheduler.scheduleRules.count, 1)
        XCTAssertEqual(scheduler.scheduleRules.first?.id, rule.id)
    }

    /// Tests removing a schedule rule by ID.
    func testRemoveScheduleRule() {
        // Add two rules
        let rule1 = makeTestRule()
        let rule2 = makeTestRule()
        scheduler.addScheduleRule(rule1)
        scheduler.addScheduleRule(rule2)
        XCTAssertEqual(scheduler.scheduleRules.count, 2)
        // Remove the first rule
        scheduler.removeScheduleRule(id: rule1.id)
        // Only the second should remain
        XCTAssertEqual(scheduler.scheduleRules.count, 1)
        XCTAssertEqual(scheduler.scheduleRules.first?.id, rule2.id)
    }

    /// Tests removing a non-existent rule ID is a no-op.
    func testRemoveNonExistentRule() {
        // Add a rule
        let rule = makeTestRule()
        scheduler.addScheduleRule(rule)
        // Remove with a different UUID
        scheduler.removeScheduleRule(id: UUID())
        // Original rule should still be there
        XCTAssertEqual(scheduler.scheduleRules.count, 1)
    }

    // MARK: - Schedule Evaluation

    /// Tests that evaluateSchedules activates caffeination when a rule matches.
    func testEvaluateSchedulesActivates() {
        // Create a rule that's always active (all days, 00:00-23:59)
        var start = DateComponents()
        start.hour = 0
        start.minute = 0
        var end = DateComponents()
        end.hour = 23
        end.minute = 59
        let rule = ScheduleRule(
            weekdays: Set(Weekday.allCases),
            startTime: start,
            endTime: end
        )
        // Add the rule
        scheduler.addScheduleRule(rule)
        // Manually evaluate (the timer-based evaluation is tested separately)
        scheduler.evaluateSchedules()
        // Should be caffeinated since the rule is active right now
        XCTAssertTrue(scheduler.powerManager.state.isActive)
    }

    /// Tests that evaluateSchedules does not deactivate user-initiated caffeination.
    func testEvaluateSchedulesDoesNotOverrideUserCaffeination() throws {
        // User-initiated caffeination
        try scheduler.startTimed(.oneHour)
        // Add a rule that's NOT active right now (past time window)
        var start = DateComponents()
        start.hour = 0
        start.minute = 0
        var end = DateComponents()
        end.hour = 0
        end.minute = 1
        let rule = ScheduleRule(
            weekdays: Set(Weekday.allCases),
            startTime: start,
            endTime: end
        )
        scheduler.addScheduleRule(rule)
        // Evaluate schedules — should not deactivate user's caffeination
        scheduler.evaluateSchedules()
        // Should still be caffeinated (user-initiated)
        XCTAssertTrue(scheduler.powerManager.state.isActive)
    }

    // MARK: - Mode Switching

    /// Tests switching from timed to app-watching mode.
    func testSwitchFromTimedToAppWatching() throws {
        // Start timed
        try scheduler.startTimed(.fifteenMinutes)
        XCTAssertTrue(scheduler.powerManager.state.isActive)
        // Switch to app watching
        try scheduler.startWhileAppRunning(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        // Should now be in app-watching mode
        if case .caffeinatedWhileRunning = scheduler.powerManager.state {
            // Expected
        } else {
            XCTFail("Expected caffeinatedWhileRunning state")
        }
        // Should have released the timed assertion and created a new one
        XCTAssertEqual(mockProvider.createCallCount, 2)
        XCTAssertEqual(mockProvider.releaseCallCount, 1)
    }

    // MARK: - Helpers

    /// Creates a test ScheduleRule with a unique ID.
    ///
    /// - Returns: A ScheduleRule configured for weekdays 09:00-17:00.
    private func makeTestRule() -> ScheduleRule {
        var start = DateComponents()
        start.hour = 9
        start.minute = 0
        var end = DateComponents()
        end.hour = 17
        end.minute = 0
        return ScheduleRule(
            weekdays: [.monday, .wednesday, .friday],
            startTime: start,
            endTime: end
        )
    }
}
