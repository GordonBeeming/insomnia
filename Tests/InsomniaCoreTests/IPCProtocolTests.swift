// IPCProtocolTests.swift — InsomniaCoreTests
//
// Tests Codable round-trip encoding/decoding for all IPCCommand
// and IPCResponse variants. Ensures the IPC protocol is correctly
// serialized and deserialized for Unix domain socket transport.

import XCTest
@testable import InsomniaCore

/// Tests for IPC protocol Codable conformance.
final class IPCProtocolTests: XCTestCase {
    /// JSON encoder used across all tests.
    let encoder = JSONEncoder()
    /// JSON decoder used across all tests.
    let decoder = JSONDecoder()

    // MARK: - IPCCommand Round-Trips

    /// Tests encoding/decoding the .caffeinate command.
    func testCaffeinateCommandRoundTrip() throws {
        // Encode and decode .caffeinate
        let command = IPCCommand.caffeinate
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .decaffeinate command.
    func testDecaffeinateCommandRoundTrip() throws {
        // Encode and decode .decaffeinate
        let command = IPCCommand.decaffeinate
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .toggle command.
    func testToggleCommandRoundTrip() throws {
        // Encode and decode .toggle
        let command = IPCCommand.toggle
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .caffeinateFor command with an associated value.
    func testCaffeinateForCommandRoundTrip() throws {
        // Encode and decode .caffeinateFor with 3600 seconds
        let command = IPCCommand.caffeinateFor(seconds: 3600)
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .caffeinateUntil command with a Date.
    func testCaffeinateUntilCommandRoundTrip() throws {
        // Use a fixed date for deterministic testing
        let date = Date(timeIntervalSince1970: 1700000000)
        let command = IPCCommand.caffeinateUntil(date: date)
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .caffeinateWhile command.
    func testCaffeinateWhileCommandRoundTrip() throws {
        // Encode and decode .caffeinateWhile with a bundle ID
        let command = IPCCommand.caffeinateWhile(bundleIdentifier: "com.apple.Xcode")
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .status command.
    func testStatusCommandRoundTrip() throws {
        // Encode and decode .status
        let command = IPCCommand.status
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .addSchedule command with a ScheduleRule.
    func testAddScheduleCommandRoundTrip() throws {
        // Create a schedule rule for the test
        let rule = makeTestRule()
        let command = IPCCommand.addSchedule(rule)
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .removeSchedule command with a UUID.
    func testRemoveScheduleCommandRoundTrip() throws {
        // Use a fixed UUID for deterministic testing
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        let command = IPCCommand.removeSchedule(id: id)
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    /// Tests encoding/decoding the .listSchedules command.
    func testListSchedulesCommandRoundTrip() throws {
        // Encode and decode .listSchedules
        let command = IPCCommand.listSchedules
        let decoded = try roundTrip(command)
        XCTAssertEqual(decoded, command)
    }

    // MARK: - IPCResponse Round-Trips

    /// Tests encoding/decoding the .success response.
    func testSuccessResponseRoundTrip() throws {
        // Encode and decode .success with a message
        let response = IPCResponse.success(message: "Caffeinated indefinitely")
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .status response with decaffeinated state.
    func testStatusResponseDecaffeinatedRoundTrip() throws {
        // Encode and decode .status with decaffeinated state
        let response = IPCResponse.status(.decaffeinated, schedules: [])
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .status response with caffeinated state and schedules.
    func testStatusResponseCaffeinatedWithSchedules() throws {
        // Create a status response with schedules
        let rule = makeTestRule()
        let response = IPCResponse.status(
            .caffeinatedIndefinitely,
            schedules: [rule]
        )
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .status response with timed caffeination.
    func testStatusResponseTimedRoundTrip() throws {
        // Timed state with a fixed date
        let date = Date(timeIntervalSince1970: 1700000000)
        let response = IPCResponse.status(.caffeinatedUntil(date), schedules: [])
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .status response with app-watching state.
    func testStatusResponseAppWatchingRoundTrip() throws {
        // App-watching state
        let state = PowerState.caffeinatedWhileRunning(
            bundleIdentifier: "com.apple.Safari",
            appName: "Safari"
        )
        let response = IPCResponse.status(state, schedules: [])
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .scheduleList response.
    func testScheduleListResponseRoundTrip() throws {
        // Schedule list with one rule
        let rule = makeTestRule()
        let response = IPCResponse.scheduleList([rule])
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    /// Tests encoding/decoding the .error response.
    func testErrorResponseRoundTrip() throws {
        // Error response with a message
        let response = IPCResponse.error(message: "Something went wrong")
        let decoded = try roundTripResponse(response)
        XCTAssertEqual(decoded, response)
    }

    // MARK: - Helpers

    /// Encodes and decodes an IPCCommand, returning the decoded result.
    ///
    /// - Parameter command: The command to round-trip.
    /// - Returns: The decoded command.
    private func roundTrip(_ command: IPCCommand) throws -> IPCCommand {
        let data = try encoder.encode(command)
        return try decoder.decode(IPCCommand.self, from: data)
    }

    /// Encodes and decodes an IPCResponse, returning the decoded result.
    ///
    /// - Parameter response: The response to round-trip.
    /// - Returns: The decoded response.
    private func roundTripResponse(_ response: IPCResponse) throws -> IPCResponse {
        let data = try encoder.encode(response)
        return try decoder.decode(IPCResponse.self, from: data)
    }

    /// Creates a test ScheduleRule with predictable values.
    ///
    /// - Returns: A ScheduleRule configured for weekdays 09:00-17:00.
    private func makeTestRule() -> ScheduleRule {
        // Use a fixed UUID for deterministic testing
        var start = DateComponents()
        start.hour = 9
        start.minute = 0
        var end = DateComponents()
        end.hour = 17
        end.minute = 0
        return ScheduleRule(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            weekdays: [.monday, .wednesday, .friday],
            startTime: start,
            endTime: end,
            assertionType: .preventUserIdleSystemSleep
        )
    }
}
