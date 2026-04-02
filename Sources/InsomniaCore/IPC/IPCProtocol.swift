// IPCProtocol.swift — InsomniaCore
//
// Defines the command/response protocol used for inter-process communication
// between the CLI and GUI via Unix domain sockets. All messages are Codable
// for JSON serialization over the socket wire format.

import Foundation

/// Commands that can be sent from the CLI to the GUI via IPC.
///
/// Each case represents a distinct operation that the GUI's caffeination
/// scheduler can perform. Commands are serialized as JSON for transport.
public enum IPCCommand: Codable, Equatable, Sendable {
    /// Start indefinite caffeination.
    case caffeinate
    /// Stop all caffeination.
    case decaffeinate
    /// Toggle between caffeinated and decaffeinated states.
    case toggle
    /// Start timed caffeination for the specified number of seconds.
    case caffeinateFor(seconds: TimeInterval)
    /// Start timed caffeination until the specified date.
    case caffeinateUntil(date: Date)
    /// Start caffeination that lasts while the specified app is running.
    case caffeinateWhile(bundleIdentifier: String)
    /// Query the current caffeination status.
    case status
    /// Add a new schedule rule for automatic caffeination.
    case addSchedule(ScheduleRule)
    /// Remove a schedule rule by its UUID.
    case removeSchedule(id: UUID)
    /// List all configured schedule rules.
    case listSchedules
}

/// Responses sent from the GUI back to the CLI via IPC.
///
/// Each case carries the relevant data for the command that was executed.
/// Responses are serialized as JSON for transport.
public enum IPCResponse: Codable, Equatable, Sendable {
    /// The command was executed — includes a human-readable message.
    case success(message: String)
    /// Status response containing the current power state and schedule rules.
    case status(PowerState, schedules: [ScheduleRule])
    /// List of all configured schedule rules.
    case scheduleList([ScheduleRule])
    /// An error occurred — includes a human-readable error message.
    case error(message: String)
}
