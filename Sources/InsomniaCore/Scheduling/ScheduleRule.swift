// ScheduleRule.swift — InsomniaCore
//
// Defines schedule rules for automatic caffeination based on day-of-week
// and time-of-day windows. The scheduler evaluates these rules periodically
// to activate or deactivate caffeination on a recurring schedule.

import Foundation

// MARK: - Weekday Enum

/// Represents days of the week, aligned with `Calendar`'s weekday numbering.
///
/// Sunday = 1, Monday = 2, ..., Saturday = 7, matching `DateComponents.weekday`.
public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    /// Sunday — Calendar weekday 1
    case sunday = 1
    /// Monday — Calendar weekday 2
    case monday = 2
    /// Tuesday — Calendar weekday 3
    case tuesday = 3
    /// Wednesday — Calendar weekday 4
    case wednesday = 4
    /// Thursday — Calendar weekday 5
    case thursday = 5
    /// Friday — Calendar weekday 6
    case friday = 6
    /// Saturday — Calendar weekday 7
    case saturday = 7

    /// Short display name for UI labels (e.g., "Mon", "Tue").
    public var shortName: String {
        switch self {
        case .sunday: return "Sun"
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        }
    }

    /// Comparable conformance — compares raw integer values.
    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Schedule Rule

/// A rule that defines when automatic caffeination should be active.
///
/// Each rule specifies a set of weekdays and a time window (start/end).
/// The scheduler checks these rules periodically and activates/deactivates
/// caffeination based on whether the current time falls within any active rule.
public struct ScheduleRule: Codable, Identifiable, Equatable, Sendable {
    /// Unique identifier for this rule.
    public let id: UUID

    /// The days of the week on which this rule is active.
    public var weekdays: Set<Weekday>

    /// The start time of the caffeination window (hour and minute components).
    /// Uses `DateComponents` with `.hour` and `.minute` set.
    public var startTime: DateComponents

    /// The end time of the caffeination window (hour and minute components).
    /// Uses `DateComponents` with `.hour` and `.minute` set.
    public var endTime: DateComponents

    /// Whether this rule is currently enabled.
    /// Disabled rules are skipped during schedule evaluation.
    public var isEnabled: Bool

    /// The type of power assertion to create when this rule is active.
    public var assertionType: PowerAssertionType

    // MARK: - Initialization

    /// Creates a new schedule rule.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - weekdays: The days on which this rule applies.
    ///   - startTime: The start time (hour/minute) of the caffeination window.
    ///   - endTime: The end time (hour/minute) of the caffeination window.
    ///   - isEnabled: Whether the rule is active. Defaults to `true`.
    ///   - assertionType: The assertion type. Defaults to preventing system sleep.
    public init(
        id: UUID = UUID(),
        weekdays: Set<Weekday>,
        startTime: DateComponents,
        endTime: DateComponents,
        isEnabled: Bool = true,
        assertionType: PowerAssertionType = .preventUserIdleSystemSleep
    ) {
        self.id = id
        self.weekdays = weekdays
        self.startTime = startTime
        self.endTime = endTime
        self.isEnabled = isEnabled
        self.assertionType = assertionType
    }

    // MARK: - Evaluation

    /// Determines whether this rule is active at the given date.
    ///
    /// A rule is active when:
    /// 1. It is enabled
    /// 2. The date's weekday is in the rule's weekday set
    /// 3. The date's time falls within the start/end window
    ///
    /// Supports midnight-crossing windows (e.g., 22:00–06:00).
    ///
    /// - Parameter date: The date to check. Defaults to the current date.
    /// - Returns: `true` if the rule applies at the given date and time.
    public func isActive(at date: Date = Date()) -> Bool {
        // Disabled rules never activate
        guard isEnabled else { return false }

        // Get the current calendar for weekday/time extraction
        let calendar = Calendar.current
        // Extract the weekday component (1=Sunday ... 7=Saturday)
        let currentWeekday = calendar.component(.weekday, from: date)

        // Extract start and end times as minutes-since-midnight for comparison
        let startMinutes = (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0)
        let endMinutes = (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0)
        // Current time as minutes-since-midnight
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
        let currentMinutes = currentHour * 60 + currentMinute

        if startMinutes <= endMinutes {
            // Normal window (e.g., 09:00–17:00): same day, no midnight crossing
            guard let weekday = Weekday(rawValue: currentWeekday),
                  weekdays.contains(weekday) else {
                return false
            }
            // Check if current time is within the window
            return currentMinutes >= startMinutes && currentMinutes < endMinutes
        } else {
            // Midnight-crossing window (e.g., 22:00–06:00)
            // The rule spans two calendar days
            if currentMinutes >= startMinutes {
                // After start time — check today's weekday
                guard let weekday = Weekday(rawValue: currentWeekday),
                      weekdays.contains(weekday) else {
                    return false
                }
                return true
            } else if currentMinutes < endMinutes {
                // Before end time — this is the "next day" portion,
                // so check if yesterday's weekday was in the set
                let yesterday = calendar.date(byAdding: .day, value: -1, to: date)!
                let yesterdayWeekday = calendar.component(.weekday, from: yesterday)
                guard let weekday = Weekday(rawValue: yesterdayWeekday),
                      weekdays.contains(weekday) else {
                    return false
                }
                return true
            }
            // Outside both portions of the window
            return false
        }
    }

    // MARK: - Display

    /// A human-readable summary of the rule for display in the UI.
    ///
    /// Format: "Mon, Wed, Fri 09:00–17:00 (Prevent system sleep)"
    public var displaySummary: String {
        // Sort weekdays for consistent display order
        let dayNames = weekdays.sorted().map { $0.shortName }
        let daysString = dayNames.joined(separator: ", ")
        // Format times as HH:mm
        let startStr = formatTime(startTime)
        let endStr = formatTime(endTime)
        // Include the assertion type for clarity
        let typeStr = assertionType.displayDescription
        // Combine into a single summary line
        return "\(daysString) \(startStr)–\(endStr) (\(typeStr))"
    }

    /// Formats a `DateComponents` time value as "HH:mm".
    ///
    /// - Parameter components: The time components to format.
    /// - Returns: A zero-padded time string like "09:00" or "22:30".
    private func formatTime(_ components: DateComponents) -> String {
        // Extract hour and minute, defaulting to 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        // Zero-pad both components to two digits
        return String(format: "%02d:%02d", hour, minute)
    }
}
