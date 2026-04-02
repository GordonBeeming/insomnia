// PowerAssertionManagerTests.swift — InsomniaCoreTests
//
// Tests for PowerAssertionManager state transitions, timer-based expiry,
// toggle behavior, and mock IOKit provider interactions. Uses a mock
// provider to avoid real IOKit calls in unit tests.

import XCTest
@testable import InsomniaCore

// MARK: - Mock Power Assertion Provider

/// Mock implementation of PowerAssertionProviding for testing.
///
/// Tracks assertion creation and release calls so tests can verify
/// the manager's behavior without touching real IOKit.
final class MockPowerAssertionProvider: PowerAssertionProviding, @unchecked Sendable {
    /// Counter for generating unique assertion IDs.
    private var nextID: UInt32 = 1

    /// Number of times createAssertion was called.
    var createCallCount = 0

    /// Number of times releaseAssertion was called.
    var releaseCallCount = 0

    /// The assertion type string from the most recent create call.
    var lastAssertionType: String?

    /// The reason string from the most recent create call.
    var lastReason: String?

    /// Set of currently active assertion IDs.
    var activeAssertions: Set<UInt32> = []

    /// Whether the next createAssertion call should throw an error.
    var shouldFailCreate = false

    /// Whether the next releaseAssertion call should throw an error.
    var shouldFailRelease = false

    /// Creates a mock assertion and records the call.
    func createAssertion(type: String, reason: String) throws -> UInt32 {
        // Increment call counter for test verification
        createCallCount += 1
        lastAssertionType = type
        lastReason = reason
        // Simulate failure if configured
        if shouldFailCreate {
            throw PowerAssertionError.creationFailed(ioReturn: -1)
        }
        // Generate a unique ID and track it
        let id = nextID
        nextID += 1
        activeAssertions.insert(id)
        return id
    }

    /// Releases a mock assertion and records the call.
    func releaseAssertion(_ assertionID: UInt32) throws {
        // Increment call counter for test verification
        releaseCallCount += 1
        // Simulate failure if configured
        if shouldFailRelease {
            throw PowerAssertionError.releaseFailed(ioReturn: -1)
        }
        // Remove from active set
        activeAssertions.remove(assertionID)
    }
}

// MARK: - Tests

/// Tests for PowerAssertionManager covering state transitions and timer behavior.
final class PowerAssertionManagerTests: XCTestCase {
    /// The mock provider injected into the manager under test.
    var mockProvider: MockPowerAssertionProvider!
    /// The manager instance being tested.
    var manager: PowerAssertionManager!

    /// Sets up a fresh mock provider and manager before each test.
    override func setUp() {
        super.setUp()
        // Create fresh instances for test isolation
        mockProvider = MockPowerAssertionProvider()
        manager = PowerAssertionManager(provider: mockProvider)
    }

    /// Cleans up test resources after each test.
    override func tearDown() {
        manager = nil
        mockProvider = nil
        super.tearDown()
    }

    // MARK: - Initial State

    /// Verifies the manager starts in the decaffeinated state.
    func testInitialStateIsDecaffeinated() {
        // Manager should start inactive
        XCTAssertEqual(manager.state, .decaffeinated)
        XCTAssertFalse(manager.state.isActive)
        XCTAssertNil(manager.currentAssertionType)
    }

    // MARK: - Caffeinate Indefinitely

    /// Tests that calling caffeinate() transitions to the caffeinatedIndefinitely state.
    func testCaffeinateIndefinitely() throws {
        // Caffeinate with default type
        try manager.caffeinate()
        // Verify state transition
        XCTAssertEqual(manager.state, .caffeinatedIndefinitely)
        XCTAssertTrue(manager.state.isActive)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleSystemSleep)
        // Verify the mock was called
        XCTAssertEqual(mockProvider.createCallCount, 1)
        XCTAssertEqual(mockProvider.activeAssertions.count, 1)
    }

    /// Tests caffeination with display sleep prevention type.
    func testCaffeinateWithDisplaySleepType() throws {
        // Caffeinate with display sleep type
        try manager.caffeinate(type: .preventUserIdleDisplaySleep)
        // Verify the correct assertion type was used
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleDisplaySleep)
        XCTAssertEqual(mockProvider.lastAssertionType, PowerAssertionType.preventUserIdleDisplaySleep.iokitAssertionType)
    }

    // MARK: - Caffeinate For Duration

    /// Tests timed caffeination sets the correct state with an end date.
    func testCaffeinateForDuration() throws {
        // Caffeinate for 60 seconds
        try manager.caffeinate(for: 60)
        // Verify state is timed (caffeinatedUntil)
        if case .caffeinatedUntil(let date) = manager.state {
            // The end date should be approximately 60 seconds from now
            let expected = Date().addingTimeInterval(60)
            XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 2)
        } else {
            XCTFail("Expected caffeinatedUntil state, got \(manager.state)")
        }
        // Verify the mock was called
        XCTAssertEqual(mockProvider.createCallCount, 1)
    }

    // MARK: - Caffeinate Until Date

    /// Tests caffeination until a specific date.
    func testCaffeinateUntilDate() throws {
        // Set a target date 2 hours from now
        let targetDate = Date().addingTimeInterval(7200)
        try manager.caffeinate(until: targetDate)
        // Verify state contains the correct end date
        XCTAssertEqual(manager.state, .caffeinatedUntil(targetDate))
        XCTAssertEqual(manager.state.endDate, targetDate)
    }

    // MARK: - Decaffeinate

    /// Tests that decaffeinate releases the assertion and resets state.
    func testDecaffeinate() throws {
        // First caffeinate
        try manager.caffeinate()
        XCTAssertTrue(manager.state.isActive)
        // Then decaffeinate
        try manager.decaffeinate()
        // Verify state reset
        XCTAssertEqual(manager.state, .decaffeinated)
        XCTAssertFalse(manager.state.isActive)
        XCTAssertNil(manager.currentAssertionType)
        // Verify the mock was called for both create and release
        XCTAssertEqual(mockProvider.createCallCount, 1)
        XCTAssertEqual(mockProvider.releaseCallCount, 1)
        XCTAssertTrue(mockProvider.activeAssertions.isEmpty)
    }

    /// Tests that decaffeinating when already decaffeinated is a no-op.
    func testDecaffeinateWhenAlreadyDecaffeinated() throws {
        // Should not throw — it's a no-op
        try manager.decaffeinate()
        XCTAssertEqual(manager.state, .decaffeinated)
        // No release should have been called
        XCTAssertEqual(mockProvider.releaseCallCount, 0)
    }

    // MARK: - Toggle

    /// Tests toggle from decaffeinated to caffeinated.
    func testToggleFromDecaffeinated() throws {
        // Toggle should caffeinate
        try manager.toggle()
        XCTAssertEqual(manager.state, .caffeinatedIndefinitely)
        XCTAssertEqual(mockProvider.createCallCount, 1)
    }

    /// Tests toggle from caffeinated to decaffeinated.
    func testToggleFromCaffeinated() throws {
        // First caffeinate
        try manager.caffeinate()
        // Toggle should decaffeinate
        try manager.toggle()
        XCTAssertEqual(manager.state, .decaffeinated)
        XCTAssertEqual(mockProvider.releaseCallCount, 1)
    }

    /// Tests double toggle returns to original state.
    func testDoubleToggle() throws {
        // Toggle twice should return to the original state
        try manager.toggle()
        try manager.toggle()
        XCTAssertEqual(manager.state, .decaffeinated)
    }

    // MARK: - Replacing Assertions

    /// Tests that caffeinating while already caffeinated replaces the assertion.
    func testReplacingAssertion() throws {
        // Caffeinate first time
        try manager.caffeinate(type: .preventUserIdleSystemSleep)
        XCTAssertEqual(mockProvider.createCallCount, 1)
        // Caffeinate again with different type — should release first
        try manager.caffeinate(type: .preventUserIdleDisplaySleep)
        XCTAssertEqual(mockProvider.createCallCount, 2)
        XCTAssertEqual(mockProvider.releaseCallCount, 1)
        // Only one assertion should be active
        XCTAssertEqual(mockProvider.activeAssertions.count, 1)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleDisplaySleep)
    }

    // MARK: - App Watching State

    /// Tests caffeination while an app is running sets the correct state.
    func testCaffeinateWhileRunning() throws {
        // Start app-watching caffeination
        try manager.caffeinateWhileRunning(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        // Verify state
        if case .caffeinatedWhileRunning(let bundleID, let name) = manager.state {
            XCTAssertEqual(bundleID, "com.apple.Safari")
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected caffeinatedWhileRunning state, got \(manager.state)")
        }
        XCTAssertTrue(manager.state.isActive)
    }

    // MARK: - Error Handling

    /// Tests that create failure propagates the error and doesn't change state.
    func testCreateAssertionFailure() {
        // Configure mock to fail
        mockProvider.shouldFailCreate = true
        // Attempt to caffeinate — should throw
        XCTAssertThrowsError(try manager.caffeinate()) { error in
            // Verify it's the expected error type
            guard case PowerAssertionError.creationFailed = error else {
                XCTFail("Expected creationFailed error")
                return
            }
        }
        // State should remain decaffeinated
        XCTAssertEqual(manager.state, .decaffeinated)
    }
}
