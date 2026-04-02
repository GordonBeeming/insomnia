// PowerState.swift — InsomniaCore
//
// Represents the current caffeination state of the application.
// This enum is the central state object observed by both the GUI and CLI
// to determine what the power manager is currently doing.

import Foundation

/// The current caffeination state of the Insomnia application.
///
/// Each case represents a distinct mode of operation, from fully inactive
/// (decaffeinated) to various active modes with different expiry conditions.
public enum PowerState: Codable, Equatable, Sendable {
    /// The application is not preventing sleep — the system behaves normally.
    case decaffeinated

    /// Sleep prevention is active with no automatic expiry.
    /// The user must manually decaffeinate.
    case caffeinatedIndefinitely

    /// Sleep prevention is active until the specified date.
    /// The power manager will automatically decaffeinate when the date passes.
    case caffeinatedUntil(Date)

    /// Sleep prevention is active while a specific application is running.
    /// When the watched app terminates, caffeination ends automatically.
    case caffeinatedWhileRunning(bundleIdentifier: String, appName: String)

    // MARK: - Computed Properties

    /// A human-readable description of the current state for display in the UI.
    ///
    /// Returns a string suitable for showing in the menu bar or status area.
    public var displayDescription: String {
        switch self {
        case .decaffeinated:
            // Inactive state label
            return "Decaffeinated"
        case .caffeinatedIndefinitely:
            // Indefinite caffeination label
            return "Caffeinated indefinitely"
        case .caffeinatedUntil(let date):
            // Timed caffeination — include the target time
            let formatter = DateFormatter()
            // Use short time style for compact display
            formatter.timeStyle = .short
            formatter.dateStyle = .short
            return "Caffeinated until \(formatter.string(from: date))"
        case .caffeinatedWhileRunning(_, let appName):
            // App-watching mode — show which app is being watched
            return "Caffeinated while \(appName) is running"
        }
    }

    /// Whether caffeination is currently active (any mode except decaffeinated).
    public var isActive: Bool {
        switch self {
        case .decaffeinated:
            // Only decaffeinated is inactive
            return false
        case .caffeinatedIndefinitely, .caffeinatedUntil, .caffeinatedWhileRunning:
            // All other states are actively preventing sleep
            return true
        }
    }

    /// The date at which caffeination will automatically end, if applicable.
    ///
    /// Returns `nil` for decaffeinated, indefinite, and app-watching modes
    /// since they don't have a fixed end date.
    public var endDate: Date? {
        switch self {
        case .caffeinatedUntil(let date):
            // Only timed caffeination has an end date
            return date
        case .decaffeinated, .caffeinatedIndefinitely, .caffeinatedWhileRunning:
            // These modes don't have a scheduled end time
            return nil
        }
    }

    /// A description of the remaining time for timed caffeination.
    ///
    /// Returns `nil` if the state doesn't have a timed component.
    /// Uses `RelativeDateTimeFormatter` for natural language output like "in 2 hours".
    public var remainingDescription: String? {
        guard let endDate = endDate else {
            // No end date means no remaining time to describe
            return nil
        }
        // Calculate the time interval from now to the end date
        let remaining = endDate.timeIntervalSinceNow
        if remaining <= 0 {
            // The timer has expired
            return "Expired"
        }
        // Format as a human-readable relative time string
        let formatter = RelativeDateTimeFormatter()
        // Use a short, numeric style for compact display
        formatter.unitsStyle = .full
        return formatter.localizedString(for: endDate, relativeTo: Date())
    }
}
