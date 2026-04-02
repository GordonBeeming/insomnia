// PowerAssertionIntegrationTests.swift — InsomniaIntegrationTests
//
// Integration tests that exercise real IOKit power assertions on macOS.
// These tests actually create and release power assertions, momentarily
// preventing the system from sleeping. They verify that the
// PowerAssertionManager correctly manages IOKit resources end-to-end.

import XCTest
@testable import InsomniaCore

/// Integration tests using real IOKit power assertions.
///
/// These tests exercise the actual IOPMAssertionCreate/Release path
/// via IOKitPowerAssertionProvider. They require macOS with IOKit
/// available and may briefly prevent sleep while running.
final class PowerAssertionIntegrationTests: XCTestCase {
    /// The manager under test, using real IOKit assertions.
    var manager: PowerAssertionManager!

    /// Creates a fresh manager with the real IOKit provider before each test.
    override func setUp() {
        super.setUp()
        // Use the real IOKit provider for integration testing
        manager = PowerAssertionManager(provider: IOKitPowerAssertionProvider.shared)
    }

    /// Releases any active assertion and cleans up after each test.
    override func tearDown() {
        // Ensure we don't leave dangling assertions after test failures
        try? manager.decaffeinate()
        manager = nil
        super.tearDown()
    }

    // MARK: - Caffeinate / Decaffeinate Lifecycle

    /// Tests that a real IOKit assertion can be created and the state updates.
    func testCaffeinateCreatesRealAssertion() throws {
        try manager.caffeinate()
        XCTAssertEqual(manager.state, .caffeinatedIndefinitely)
        XCTAssertTrue(manager.state.isActive)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleSystemSleep)
    }

    /// Tests that decaffeinate releases the real IOKit assertion.
    func testDecaffeinateReleasesRealAssertion() throws {
        // Create a real assertion
        try manager.caffeinate()
        XCTAssertTrue(manager.state.isActive)

        // Release it
        try manager.decaffeinate()
        XCTAssertEqual(manager.state, .decaffeinated)
        XCTAssertFalse(manager.state.isActive)
        XCTAssertNil(manager.currentAssertionType)
    }

    // MARK: - Toggle

    /// Tests toggling with real IOKit assertions.
    func testToggleWithRealAssertions() throws {
        // Start decaffeinated
        XCTAssertFalse(manager.state.isActive)

        // Toggle on
        try manager.toggle()
        XCTAssertTrue(manager.state.isActive)
        XCTAssertEqual(manager.state, .caffeinatedIndefinitely)

        // Toggle off
        try manager.toggle()
        XCTAssertFalse(manager.state.isActive)
        XCTAssertEqual(manager.state, .decaffeinated)
    }

    // MARK: - Timed Caffeination

    /// Tests that timed caffeination auto-decaffeinates after the duration expires.
    ///
    /// This test waits for the timer to fire, so it's intentionally slow.
    func testTimedCaffeinationAutoExpires() throws {
        // Caffeinate for 2 seconds
        try manager.caffeinate(for: 2)
        XCTAssertTrue(manager.state.isActive)

        // Verify the state is timed
        if case .caffeinatedUntil = manager.state {
            // expected
        } else {
            XCTFail("Expected caffeinatedUntil state, got \(manager.state)")
        }

        // Wait 3 seconds for the timer to fire
        let expectation = XCTestExpectation(description: "Wait for timed expiry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        // State should have auto-reverted to decaffeinated
        XCTAssertEqual(manager.state, .decaffeinated, "Should auto-decaffeinate after timer expires")
    }

    // MARK: - Assertion Replacement

    /// Tests that caffeinating twice releases the first assertion before creating the second.
    func testDoubleCaffeinateReplacesAssertion() throws {
        // Create first assertion (system sleep)
        try manager.caffeinate(type: .preventUserIdleSystemSleep)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleSystemSleep)

        // Create second assertion (display sleep) — should release the first
        try manager.caffeinate(type: .preventUserIdleDisplaySleep)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleDisplaySleep)
        XCTAssertTrue(manager.state.isActive)

        // Clean up
        try manager.decaffeinate()
        XCTAssertFalse(manager.state.isActive)
    }

    // MARK: - Display Sleep Prevention

    /// Tests creating a display sleep prevention assertion.
    func testDisplaySleepPrevention() throws {
        try manager.caffeinate(type: .preventUserIdleDisplaySleep)
        XCTAssertEqual(manager.currentAssertionType, .preventUserIdleDisplaySleep)
        XCTAssertTrue(manager.state.isActive)
    }

    // MARK: - Caffeinate Until

    /// Tests caffeination until a future date with a real assertion.
    func testCaffeinateUntilFutureDate() throws {
        let futureDate = Date().addingTimeInterval(300)
        try manager.caffeinate(until: futureDate)

        if case .caffeinatedUntil(let date) = manager.state {
            XCTAssertEqual(
                date.timeIntervalSince1970,
                futureDate.timeIntervalSince1970,
                accuracy: 1,
                "End date should match the requested future date"
            )
        } else {
            XCTFail("Expected caffeinatedUntil state, got \(manager.state)")
        }
    }

    // MARK: - App Watching State

    /// Tests setting app-watching state with a real assertion.
    func testCaffeinateWhileRunningWithRealAssertion() throws {
        try manager.caffeinateWhileRunning(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )

        if case .caffeinatedWhileRunning(let bundleID, let name) = manager.state {
            XCTAssertEqual(bundleID, "com.apple.Safari")
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected caffeinatedWhileRunning state, got \(manager.state)")
        }
        XCTAssertTrue(manager.state.isActive)
    }
}
