// DurationOption.swift — InsomniaCore
//
// Defines preset and custom duration options for timed caffeination.
// Includes a parser that handles human-readable duration strings like
// "15m", "2h", "90s", "1h30m" for use by the CLI and IPC interfaces.

import Foundation

/// Represents a duration for timed caffeination.
///
/// Provides preset durations for common use cases and a custom option
/// for arbitrary intervals. Includes parsing support for human-readable strings.
public enum DurationOption: Equatable, Sendable {
    /// Fifteen minutes (900 seconds).
    case fifteenMinutes
    /// Thirty minutes (1800 seconds).
    case thirtyMinutes
    /// One hour (3600 seconds).
    case oneHour
    /// Two hours (7200 seconds).
    case twoHours
    /// A custom duration specified as a time interval in seconds.
    case custom(TimeInterval)

    /// The duration in seconds as a `TimeInterval`.
    ///
    /// Used to calculate end dates and schedule timers.
    public var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes:
            // 15 * 60 = 900 seconds
            return 900
        case .thirtyMinutes:
            // 30 * 60 = 1800 seconds
            return 1_800
        case .oneHour:
            // 60 * 60 = 3600 seconds
            return 3_600
        case .twoHours:
            // 120 * 60 = 7200 seconds
            return 7_200
        case .custom(let interval):
            // User-specified interval in seconds
            return interval
        }
    }

    /// A human-readable label for display in the UI.
    ///
    /// Preset durations use simple labels; custom durations format the
    /// interval into a readable hours/minutes/seconds string.
    public var displayLabel: String {
        switch self {
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .oneHour:
            return "1 hour"
        case .twoHours:
            return "2 hours"
        case .custom(let interval):
            // Format the custom interval into a readable string
            return DurationOption.formatInterval(interval)
        }
    }

    /// All preset duration options, excluding custom.
    ///
    /// Useful for building UI menus with standard choices.
    public static var presets: [DurationOption] {
        // Return the four preset durations in ascending order
        return [.fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours]
    }

    // MARK: - Parsing

    /// Errors that can occur when parsing duration strings.
    public enum ParseError: Error, LocalizedError, Equatable {
        /// The input string was empty or contained only whitespace.
        case emptyInput
        /// The input string could not be parsed as a valid duration.
        case invalidFormat(String)
        /// The parsed duration was zero or negative.
        case nonPositiveDuration

        /// Human-readable error description for user-facing messages.
        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "Duration string cannot be empty"
            case .invalidFormat(let input):
                return "Invalid duration format: '\(input)'. Use formats like 15m, 2h, 90s, 1h30m"
            case .nonPositiveDuration:
                return "Duration must be positive"
            }
        }
    }

    /// Parses a human-readable duration string into a `DurationOption`.
    ///
    /// Supported formats:
    /// - `"15m"` — 15 minutes
    /// - `"2h"` — 2 hours
    /// - `"90s"` — 90 seconds
    /// - `"1h30m"` — 1 hour and 30 minutes
    /// - `"1h30m45s"` — 1 hour, 30 minutes, and 45 seconds
    ///
    /// - Parameter string: The duration string to parse.
    /// - Returns: A `DurationOption` representing the parsed duration.
    /// - Throws: `ParseError` if the string cannot be parsed.
    public static func parse(_ string: String) throws -> DurationOption {
        // Trim whitespace and normalize to lowercase
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        // Reject empty input
        guard !trimmed.isEmpty else {
            throw ParseError.emptyInput
        }

        // Track accumulated seconds from each component
        var totalSeconds: TimeInterval = 0
        // Track whether we matched any component
        var matched = false

        // Regex pattern matching one or more number+unit pairs
        let pattern = #"(\d+(?:\.\d+)?)\s*(h|m|s)"#
        // Create the regex for matching duration components
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ParseError.invalidFormat(string)
        }

        // Find all matches in the input string
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = regex.matches(in: trimmed, range: range)

        // Process each matched component (e.g., "1h", "30m", "45s")
        for match in matches {
            // Extract the numeric value
            guard let valueRange = Range(match.range(at: 1), in: trimmed),
                  let unitRange = Range(match.range(at: 2), in: trimmed),
                  let value = Double(trimmed[valueRange]) else {
                continue
            }
            // Extract the unit character
            let unit = String(trimmed[unitRange])
            // Convert to seconds based on the unit
            switch unit {
            case "h":
                // Hours to seconds
                totalSeconds += value * 3_600
            case "m":
                // Minutes to seconds
                totalSeconds += value * 60
            case "s":
                // Already in seconds
                totalSeconds += value
            default:
                // Regex guarantees h/m/s, but handle gracefully
                continue
            }
            // At least one component was successfully parsed
            matched = true
        }

        // If no components matched, the format is invalid
        guard matched else {
            throw ParseError.invalidFormat(string)
        }
        // Duration must be positive
        guard totalSeconds > 0 else {
            throw ParseError.nonPositiveDuration
        }

        // Map to preset durations if they match exactly
        switch totalSeconds {
        case 900:
            return .fifteenMinutes
        case 1_800:
            return .thirtyMinutes
        case 3_600:
            return .oneHour
        case 7_200:
            return .twoHours
        default:
            // Custom duration for non-preset values
            return .custom(totalSeconds)
        }
    }

    // MARK: - Private Helpers

    /// Formats a time interval in seconds into a human-readable string.
    ///
    /// - Parameter interval: The duration in seconds.
    /// - Returns: A string like "1 hour 30 minutes" or "90 seconds".
    private static func formatInterval(_ interval: TimeInterval) -> String {
        // Convert to integer components
        let totalSecs = Int(interval)
        let hours = totalSecs / 3_600
        let minutes = (totalSecs % 3_600) / 60
        let seconds = totalSecs % 60

        // Build the components array for non-zero parts
        var parts: [String] = []
        if hours > 0 {
            // Add hours component
            parts.append("\(hours) hour\(hours == 1 ? "" : "s")")
        }
        if minutes > 0 {
            // Add minutes component
            parts.append("\(minutes) minute\(minutes == 1 ? "" : "s")")
        }
        if seconds > 0 || parts.isEmpty {
            // Add seconds component (always shown if nothing else)
            parts.append("\(seconds) second\(seconds == 1 ? "" : "s")")
        }
        // Join with spaces for natural reading
        return parts.joined(separator: " ")
    }
}
