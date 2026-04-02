// IPCIntegrationTests.swift — InsomniaIntegrationTests
//
// Integration tests for the IPC command handling pipeline. Tests the full
// path from IPCCommand through IPCServer.handle() to CaffeinationScheduler
// and back to IPCResponse, using a mocked PowerAssertionManager.
//
// Note: The IPCServer uses DispatchSource on the main queue for socket I/O.
// Since XCTest runs on the main thread, calling IPCClient.send() from a test
// would deadlock (the client blocks the main thread waiting for a response
// the server can never process). These tests exercise the handle() method
// directly — the socket wire format is covered by IPCProtocolTests.

import XCTest
@testable import InsomniaCore

// MARK: - Mock Provider for IPC Tests

/// A mock power assertion provider used in IPC integration tests.
///
/// Allows the IPC server to handle commands without requiring real IOKit
/// calls, while still exercising the full command dispatch pipeline.
final class IPCMockProvider: PowerAssertionProviding, @unchecked Sendable {
    /// Counter for generating unique assertion IDs.
    private var nextID: UInt32 = 1

    /// Number of assertions currently active.
    var activeCount: Int { activeIDs.count }

    /// Set of currently active assertion IDs.
    private var activeIDs: Set<UInt32> = []

    /// Creates a mock assertion and returns a unique ID.
    func createAssertion(type: String, reason: String) throws -> UInt32 {
        let id = nextID
        nextID += 1
        activeIDs.insert(id)
        return id
    }

    /// Releases a mock assertion by its ID.
    func releaseAssertion(_ assertionID: UInt32) throws {
        activeIDs.remove(assertionID)
    }
}

// MARK: - IPC Integration Tests

/// Tests the full IPC command handling pipeline.
///
/// Each test creates a CaffeinationScheduler with a mocked power manager,
/// wraps it in an IPCServer, and calls handle() to simulate command dispatch.
/// This verifies that commands flow correctly through the scheduler and
/// produce the expected responses and state changes.
final class IPCIntegrationTests: XCTestCase {
    /// Mock provider injected into the power manager.
    var mockProvider: IPCMockProvider!
    /// Power manager backed by the mock provider.
    var powerManager: PowerAssertionManager!
    /// Scheduler that the IPC server dispatches commands to.
    var scheduler: CaffeinationScheduler!
    /// The IPC server under test (used for handle() calls only).
    var server: IPCServer!

    /// Creates a fresh server and scheduler before each test.
    override func setUp() {
        super.setUp()
        mockProvider = IPCMockProvider()
        powerManager = PowerAssertionManager(provider: mockProvider)
        scheduler = CaffeinationScheduler(powerManager: powerManager)
        // Socket path doesn't matter — we only call handle() directly
        server = IPCServer(scheduler: scheduler, socketPath: "/tmp/unused.sock")
    }

    /// Cleans up test resources after each test.
    override func tearDown() {
        server = nil
        scheduler = nil
        powerManager = nil
        mockProvider = nil
        super.tearDown()
    }

    // MARK: - Caffeinate Command

    /// Tests that .caffeinate returns success and activates the power manager.
    func testCaffeinateCommand() {
        let response = server.handle(.caffeinate)
        if case .success(let message) = response {
            XCTAssertTrue(message.contains("Caffeinated"), "Expected caffeination message")
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        XCTAssertTrue(powerManager.state.isActive, "Power manager should be active")
        XCTAssertEqual(powerManager.state, .caffeinatedIndefinitely)
    }

    // MARK: - Decaffeinate Command

    /// Tests that .decaffeinate returns success and deactivates the power manager.
    func testDecaffeinateCommand() {
        // First caffeinate
        _ = server.handle(.caffeinate)
        XCTAssertTrue(powerManager.state.isActive)

        // Then decaffeinate
        let response = server.handle(.decaffeinate)
        if case .success(let message) = response {
            XCTAssertTrue(message.contains("Decaffeinated"), "Expected decaffeination message")
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        XCTAssertFalse(powerManager.state.isActive)
        XCTAssertEqual(powerManager.state, .decaffeinated)
    }

    // MARK: - Toggle Command

    /// Tests that .toggle activates when decaffeinated, then deactivates when caffeinated.
    func testToggleCommand() {
        // Toggle on
        let onResponse = server.handle(.toggle)
        if case .success(let message) = onResponse {
            XCTAssertTrue(message.contains("Toggled"), "Expected toggle message")
        } else {
            XCTFail("Expected .success response, got \(onResponse)")
        }
        XCTAssertTrue(powerManager.state.isActive, "Should be active after first toggle")

        // Toggle off
        let offResponse = server.handle(.toggle)
        if case .success = offResponse {
            // expected
        } else {
            XCTFail("Expected .success response for second toggle, got \(offResponse)")
        }
        XCTAssertFalse(powerManager.state.isActive, "Should be inactive after second toggle")
    }

    // MARK: - CaffeinateFor Command

    /// Tests timed caffeination via .caffeinateFor sets timed state.
    func testCaffeinateForCommand() {
        let response = server.handle(.caffeinateFor(seconds: 60))
        if case .success(let message) = response {
            XCTAssertTrue(message.contains("60"), "Expected message mentioning duration")
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        // State should be timed
        if case .caffeinatedUntil(let date) = powerManager.state {
            let expected = Date().addingTimeInterval(60)
            XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 2)
        } else {
            XCTFail("Expected caffeinatedUntil state, got \(powerManager.state)")
        }
    }

    // MARK: - CaffeinateUntil Command

    /// Tests caffeination until a specific date via .caffeinateUntil.
    func testCaffeinateUntilCommand() {
        let targetDate = Date().addingTimeInterval(3600)
        let response = server.handle(.caffeinateUntil(date: targetDate))
        if case .success = response {
            // expected
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        if case .caffeinatedUntil(let date) = powerManager.state {
            XCTAssertEqual(date.timeIntervalSince1970, targetDate.timeIntervalSince1970, accuracy: 2)
        } else {
            XCTFail("Expected caffeinatedUntil state, got \(powerManager.state)")
        }
    }

    // MARK: - Status Command

    /// Tests .status returns current state and empty schedule list.
    func testStatusCommandWhenDecaffeinated() {
        let response = server.handle(.status)
        if case .status(let state, let schedules) = response {
            XCTAssertEqual(state, .decaffeinated)
            XCTAssertTrue(schedules.isEmpty)
        } else {
            XCTFail("Expected .status response, got \(response)")
        }
    }

    /// Tests .status reflects active caffeination state.
    func testStatusReflectsActiveCaffeination() {
        _ = server.handle(.caffeinate)
        let response = server.handle(.status)
        if case .status(let state, _) = response {
            XCTAssertTrue(state.isActive)
            XCTAssertEqual(state, .caffeinatedIndefinitely)
        } else {
            XCTFail("Expected .status response, got \(response)")
        }
    }

    /// Tests .status includes schedule rules when present.
    func testStatusIncludesSchedules() {
        let rule = makeTestScheduleRule()
        scheduler.addScheduleRule(rule)

        let response = server.handle(.status)
        if case .status(_, let schedules) = response {
            XCTAssertEqual(schedules.count, 1)
            XCTAssertEqual(schedules.first?.id, rule.id)
        } else {
            XCTFail("Expected .status response, got \(response)")
        }
    }

    // MARK: - Schedule Commands

    /// Tests adding a schedule rule via .addSchedule.
    func testAddScheduleCommand() {
        let rule = makeTestScheduleRule()
        let response = server.handle(.addSchedule(rule))
        if case .success(let message) = response {
            XCTAssertTrue(message.contains("added"), "Expected addition confirmation")
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        XCTAssertEqual(scheduler.scheduleRules.count, 1)
        XCTAssertEqual(scheduler.scheduleRules.first?.id, rule.id)
    }

    /// Tests listing schedules via .listSchedules.
    func testListSchedulesCommand() {
        let rule1 = makeTestScheduleRule()
        let rule2 = makeTestScheduleRule()
        scheduler.addScheduleRule(rule1)
        scheduler.addScheduleRule(rule2)

        let response = server.handle(.listSchedules)
        if case .scheduleList(let schedules) = response {
            XCTAssertEqual(schedules.count, 2)
        } else {
            XCTFail("Expected .scheduleList response, got \(response)")
        }
    }

    /// Tests removing a schedule rule via .removeSchedule.
    func testRemoveScheduleCommand() {
        let rule = makeTestScheduleRule()
        scheduler.addScheduleRule(rule)
        XCTAssertEqual(scheduler.scheduleRules.count, 1)

        let response = server.handle(.removeSchedule(id: rule.id))
        if case .success(let message) = response {
            XCTAssertTrue(message.contains("removed"), "Expected removal confirmation")
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
        XCTAssertTrue(scheduler.scheduleRules.isEmpty)
    }

    /// Tests removing a non-existent schedule returns success (no-op).
    func testRemoveNonExistentSchedule() {
        let response = server.handle(.removeSchedule(id: UUID()))
        if case .success = response {
            // expected — removal of non-existent ID is a no-op
        } else {
            XCTFail("Expected .success response, got \(response)")
        }
    }

    // MARK: - Sequential Command Flows

    /// Tests a full lifecycle: caffeinate -> status -> decaffeinate -> status.
    func testFullLifecycleFlow() {
        // Start decaffeinated
        let status1 = server.handle(.status)
        if case .status(let state, _) = status1 {
            XCTAssertFalse(state.isActive)
        }

        // Caffeinate
        let caffResponse = server.handle(.caffeinate)
        if case .success = caffResponse { /* expected */ }

        // Check status while active
        let status2 = server.handle(.status)
        if case .status(let state, _) = status2 {
            XCTAssertTrue(state.isActive)
        }

        // Decaffeinate
        let decaffResponse = server.handle(.decaffeinate)
        if case .success = decaffResponse { /* expected */ }

        // Verify back to inactive
        let status3 = server.handle(.status)
        if case .status(let state, _) = status3 {
            XCTAssertFalse(state.isActive)
        }
    }

    /// Tests switching between caffeination modes via IPC.
    func testModeSwitchingViaIPC() {
        // Start with indefinite
        _ = server.handle(.caffeinate)
        XCTAssertEqual(powerManager.state, .caffeinatedIndefinitely)

        // Switch to timed
        _ = server.handle(.caffeinateFor(seconds: 120))
        if case .caffeinatedUntil = powerManager.state {
            // expected — timed mode
        } else {
            XCTFail("Expected timed mode after caffeinateFor")
        }

        // Switch to indefinite again
        _ = server.handle(.caffeinate)
        XCTAssertEqual(powerManager.state, .caffeinatedIndefinitely)

        // Decaffeinate
        _ = server.handle(.decaffeinate)
        XCTAssertEqual(powerManager.state, .decaffeinated)
    }

    // MARK: - Socket Lifecycle Tests

    /// Tests that the server can start and stop without errors on a valid path.
    func testServerStartAndStop() throws {
        let shortID = UUID().uuidString.prefix(8)
        let socketPath = "/tmp/ins-\(shortID).sock"

        let testServer = IPCServer(scheduler: scheduler, socketPath: socketPath)
        try testServer.start()

        // Socket file should exist while server is running
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))

        // Stop should clean up the socket file
        testServer.stop()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: socketPath),
            "Socket file should be removed after stop()"
        )
    }

    /// Tests that IPCClient.isGUIRunning returns false when no server is listening.
    func testClientDetectsNoServer() {
        let badClient = IPCClient(socketPath: "/tmp/ins-nonexist-\(UUID().uuidString.prefix(8)).sock")
        XCTAssertFalse(badClient.isGUIRunning, "Should detect no server running")
    }

    /// Tests that IPCClient.send throws when no server is listening.
    func testClientSendToNonExistentServerThrows() {
        let badClient = IPCClient(socketPath: "/tmp/ins-nosrv-\(UUID().uuidString.prefix(8)).sock")
        XCTAssertThrowsError(try badClient.send(.status), "Should throw when no server is available")
    }

    // MARK: - Helpers

    /// Creates a test ScheduleRule with a unique ID.
    private func makeTestScheduleRule() -> ScheduleRule {
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
