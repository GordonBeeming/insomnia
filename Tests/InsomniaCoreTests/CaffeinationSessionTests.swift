// CaffeinationSessionTests.swift — InsomniaCoreTests
//
// Tests for CaffeinationSession covering initialization, Codable
// conformance, computed properties (isActive, duration), and
// all PowerState modes.

import XCTest
@testable import InsomniaCore

/// Tests for the CaffeinationSession model.
final class CaffeinationSessionTests: XCTestCase {

    // MARK: - Initialization

    /// Tests creating a session with default values.
    func testDefaultInitialization() {
        // Create a session with required fields only
        let session = CaffeinationSession(
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep
        )
        // Verify default values
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(session.startedAt)
        XCTAssertEqual(session.mode, .caffeinatedIndefinitely)
        XCTAssertEqual(session.assertionType, .preventUserIdleSystemSleep)
        XCTAssertNil(session.endedAt)
    }

    /// Tests creating a session with all fields specified.
    func testFullInitialization() {
        // Use fixed dates for deterministic testing
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let session = CaffeinationSession(
            id: id,
            startedAt: start,
            mode: .caffeinatedUntil(end),
            assertionType: .preventUserIdleDisplaySleep,
            endedAt: end
        )
        // Verify all fields match
        XCTAssertEqual(session.id, id)
        XCTAssertEqual(session.startedAt, start)
        XCTAssertEqual(session.assertionType, .preventUserIdleDisplaySleep)
        XCTAssertEqual(session.endedAt, end)
    }

    // MARK: - isActive

    /// Tests that a session without an endedAt is active.
    func testIsActiveWhenNoEndDate() {
        // Session without endedAt should be active
        let session = CaffeinationSession(
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep
        )
        XCTAssertTrue(session.isActive)
    }

    /// Tests that a session with an endedAt is not active.
    func testIsNotActiveWhenEndDateSet() {
        // Session with endedAt should not be active
        let session = CaffeinationSession(
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep,
            endedAt: Date()
        )
        XCTAssertFalse(session.isActive)
    }

    // MARK: - Duration

    /// Tests duration calculation for a completed session.
    func testDurationForCompletedSession() {
        // Create a session that lasted exactly 1000 seconds
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let session = CaffeinationSession(
            startedAt: start,
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep,
            endedAt: end
        )
        // Duration should be exactly 1000 seconds
        XCTAssertEqual(session.duration, 1000, accuracy: 0.1)
    }

    /// Tests duration calculation for an active session (uses current time).
    func testDurationForActiveSession() {
        // Create a session started 5 seconds ago
        let start = Date().addingTimeInterval(-5)
        let session = CaffeinationSession(
            startedAt: start,
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep
        )
        // Duration should be approximately 5 seconds
        XCTAssertEqual(session.duration, 5, accuracy: 2)
    }

    // MARK: - Codable

    /// Tests Codable round-trip for a session with decaffeinated mode.
    func testCodableRoundTripDecaffeinated() throws {
        let session = CaffeinationSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1000),
            mode: .decaffeinated,
            assertionType: .preventUserIdleSystemSleep,
            endedAt: Date(timeIntervalSince1970: 2000)
        )
        // Round-trip through JSON
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CaffeinationSession.self, from: data)
        // Verify equality
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.mode, session.mode)
        XCTAssertEqual(decoded.assertionType, session.assertionType)
    }

    /// Tests Codable round-trip for a session with timed mode.
    func testCodableRoundTripTimed() throws {
        let endDate = Date(timeIntervalSince1970: 5000)
        let session = CaffeinationSession(
            startedAt: Date(timeIntervalSince1970: 1000),
            mode: .caffeinatedUntil(endDate),
            assertionType: .preventUserIdleDisplaySleep
        )
        // Round-trip through JSON
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CaffeinationSession.self, from: data)
        // Verify the mode preserved the date
        XCTAssertEqual(decoded.mode, .caffeinatedUntil(endDate))
    }

    /// Tests Codable round-trip for a session with app-watching mode.
    func testCodableRoundTripAppWatching() throws {
        let session = CaffeinationSession(
            startedAt: Date(timeIntervalSince1970: 1000),
            mode: .caffeinatedWhileRunning(
                bundleIdentifier: "com.apple.Safari",
                appName: "Safari"
            ),
            assertionType: .preventUserIdleSystemSleep
        )
        // Round-trip through JSON
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(CaffeinationSession.self, from: data)
        // Verify the mode preserved the app info
        if case .caffeinatedWhileRunning(let bundleID, let name) = decoded.mode {
            XCTAssertEqual(bundleID, "com.apple.Safari")
            XCTAssertEqual(name, "Safari")
        } else {
            XCTFail("Expected caffeinatedWhileRunning mode")
        }
    }

    // MARK: - Equatable

    /// Tests that two sessions with the same ID are equal.
    func testEquatable() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let session1 = CaffeinationSession(
            id: id,
            startedAt: date,
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep
        )
        let session2 = CaffeinationSession(
            id: id,
            startedAt: date,
            mode: .caffeinatedIndefinitely,
            assertionType: .preventUserIdleSystemSleep
        )
        XCTAssertEqual(session1, session2)
    }
}
