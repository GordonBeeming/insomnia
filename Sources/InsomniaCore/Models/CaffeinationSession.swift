// CaffeinationSession.swift — InsomniaCore
//
// A simple data model representing a single caffeination session.
// Records when caffeination started, what mode it's in, and when it ended.
// Used for history tracking, logging, and potential future analytics.

import Foundation

/// Represents a single caffeination session with start/end timestamps.
///
/// Each session records the mode (power state), assertion type, and timing
/// information. Sessions are `Codable` for persistence and `Identifiable`
/// for use in SwiftUI lists.
public struct CaffeinationSession: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for this session.
    public let id: UUID

    /// The date and time when this session started.
    public let startedAt: Date

    /// The caffeination mode that was active during this session.
    /// Captures whether it was indefinite, timed, or app-watching.
    public let mode: PowerState

    /// The type of power assertion that was active during this session.
    public let assertionType: PowerAssertionType

    /// The date and time when this session ended, if it has ended.
    /// `nil` for sessions that are still active.
    public var endedAt: Date?

    // MARK: - Initialization

    /// Creates a new caffeination session record.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - startedAt: When the session started. Defaults to now.
    ///   - mode: The caffeination mode for this session.
    ///   - assertionType: The power assertion type used.
    ///   - endedAt: When the session ended, or `nil` if still active.
    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        mode: PowerState,
        assertionType: PowerAssertionType,
        endedAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.mode = mode
        self.assertionType = assertionType
        self.endedAt = endedAt
    }

    // MARK: - Computed Properties

    /// Whether this session is still active (has not ended).
    public var isActive: Bool {
        // A session without an end date is considered active
        return endedAt == nil
    }

    /// The duration of this session in seconds.
    ///
    /// For active sessions, returns the time elapsed since the session started.
    /// For ended sessions, returns the total duration.
    public var duration: TimeInterval {
        // Use endedAt if available, otherwise calculate from now
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }
}
