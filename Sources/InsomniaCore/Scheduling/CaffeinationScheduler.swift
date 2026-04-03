// CaffeinationScheduler.swift — InsomniaCore
//
// The top-level orchestrator for all caffeination modes. Owns the
// PowerAssertionManager and AppWatcher, coordinates timed, indefinite,
// app-watching, and schedule-based caffeination. This is the primary
// entry point used by both the GUI and IPC server.

import Foundation

/// Orchestrates all caffeination modes and schedule rules.
///
/// This class is the central coordinator that manages:
/// - Indefinite caffeination (toggle on/off)
/// - Timed caffeination (for a duration or until a specific time)
/// - App-watching caffeination (while a specific app runs)
/// - Recurring schedule rules (automatic time-based activation)
///
/// Uses `@Observable` for SwiftUI integration.
@Observable
public final class CaffeinationScheduler {
    // MARK: - Properties

    /// The power assertion manager that handles IOKit interactions.
    /// Exposed as read-only for status queries.
    public let powerManager: PowerAssertionManager

    /// The app watcher for monitoring application lifecycle.
    private let appWatcher: AppWatcher

    /// The set of schedule rules for automatic caffeination.
    public private(set) var scheduleRules: [ScheduleRule] = []

    /// Timer that periodically evaluates schedule rules.
    /// Fires every 60 seconds to check if any rule should activate or deactivate.
    private var scheduleTimer: Timer?

    /// Whether the current caffeination was activated by a schedule rule.
    /// Used to avoid deactivating user-initiated caffeination when rules change.
    private var isScheduleActivated: Bool = false

    // MARK: - Initialization

    /// Creates a new caffeination scheduler.
    ///
    /// - Parameter powerManager: The power manager to use. Defaults to a new instance
    ///   with the real IOKit provider.
    public init(powerManager: PowerAssertionManager = PowerAssertionManager()) {
        // Store the power manager for assertion lifecycle management
        self.powerManager = powerManager
        // Create the app watcher for app-lifecycle monitoring
        self.appWatcher = AppWatcher()
    }

    // MARK: - Timed Caffeination

    /// Starts timed caffeination for a specific duration.
    ///
    /// - Parameters:
    ///   - duration: The duration option specifying how long to caffeinate.
    ///   - type: The assertion type. Defaults to preventing display sleep.
    /// - Throws: If the power assertion cannot be created.
    public func startTimed(
        _ duration: DurationOption,
        type: PowerAssertionType = .preventUserIdleDisplaySleep
    ) throws {
        // Mark as user-initiated (not schedule-activated)
        isScheduleActivated = false
        // Stop any app watching that might be active
        appWatcher.stopWatching()
        // Create the timed assertion via the power manager
        try powerManager.caffeinate(for: duration.timeInterval, type: type)
    }

    /// Starts caffeination until a specific date.
    ///
    /// - Parameters:
    ///   - date: The date at which caffeination should automatically end.
    ///   - type: The assertion type. Defaults to preventing display sleep.
    /// - Throws: If the power assertion cannot be created.
    public func startUntil(
        _ date: Date,
        type: PowerAssertionType = .preventUserIdleDisplaySleep
    ) throws {
        // Mark as user-initiated
        isScheduleActivated = false
        // Stop any app watching
        appWatcher.stopWatching()
        // Create the timed assertion ending at the specified date
        try powerManager.caffeinate(until: date, type: type)
    }

    // MARK: - App-Watching Caffeination

    /// Starts caffeination that lasts while a specific application is running.
    ///
    /// When the watched app terminates, caffeination is automatically stopped.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The bundle ID of the app to watch (e.g., "com.apple.Xcode").
    ///   - appName: The display name of the app (used in status messages).
    ///   - type: The assertion type. Defaults to preventing display sleep.
    /// - Throws: If the power assertion cannot be created.
    public func startWhileAppRunning(
        bundleIdentifier: String,
        appName: String? = nil,
        type: PowerAssertionType = .preventUserIdleDisplaySleep
    ) throws {
        // Mark as user-initiated
        isScheduleActivated = false
        // Resolve the display name — use provided name or derive from bundle ID
        let displayName = appName ?? bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier

        // Set up the callback for when the app terminates
        appWatcher.onWatchedAppTerminated = { [weak self] in
            // The watched app quit — decaffeinate automatically
            try? self?.powerManager.decaffeinate()
        }
        // Start watching the app
        appWatcher.watch(bundleIdentifier: bundleIdentifier)
        // Create the power assertion with app-watching state
        try powerManager.caffeinateWhileRunning(
            bundleIdentifier: bundleIdentifier,
            appName: displayName,
            type: type
        )
    }

    // MARK: - Cancel

    /// Cancels all active caffeination and stops any watches or schedule activations.
    ///
    /// - Throws: If the power assertion cannot be released.
    public func cancelAll() throws {
        // Stop watching any applications
        appWatcher.stopWatching()
        // Clear the schedule-activated flag
        isScheduleActivated = false
        // Release the power assertion
        try powerManager.decaffeinate()
    }

    // MARK: - Schedule Management

    /// Adds a schedule rule to the list of automatic caffeination rules.
    ///
    /// After adding, the schedules are immediately evaluated to check if the
    /// new rule should activate right now.
    ///
    /// - Parameter rule: The schedule rule to add.
    public func addScheduleRule(_ rule: ScheduleRule) {
        // Append the rule to the list
        scheduleRules.append(rule)
        // Start the schedule timer if not already running
        ensureScheduleTimerRunning()
        // Immediately evaluate in case the rule should be active now
        evaluateSchedules()
    }

    /// Removes a schedule rule by its unique identifier.
    ///
    /// If the removed rule was the one currently activating caffeination,
    /// schedules are re-evaluated to determine if caffeination should stop.
    ///
    /// - Parameter id: The UUID of the rule to remove.
    public func removeScheduleRule(id: UUID) {
        // Remove the rule with the matching ID
        scheduleRules.removeAll { $0.id == id }
        // Stop the timer if no rules remain
        if scheduleRules.isEmpty {
            scheduleTimer?.invalidate()
            scheduleTimer = nil
        }
        // Re-evaluate to check if caffeination should stop
        evaluateSchedules()
    }

    /// Evaluates all schedule rules against the current time.
    ///
    /// If any enabled rule is active, caffeination is started (if not already active).
    /// If no rules are active and the current caffeination was schedule-activated,
    /// caffeination is stopped.
    public func evaluateSchedules() {
        // Find the first active rule (if any)
        let activeRule = scheduleRules.first { $0.isActive() }

        if let rule = activeRule {
            // A rule is active — ensure caffeination is on
            if !powerManager.state.isActive || isScheduleActivated {
                // Either not caffeinated or already schedule-controlled — (re)activate
                try? powerManager.caffeinate(type: rule.assertionType)
                isScheduleActivated = true
            }
            // If user-initiated caffeination is active, don't override it
        } else if isScheduleActivated {
            // No active rules and caffeination was schedule-initiated — turn off
            try? powerManager.decaffeinate()
            isScheduleActivated = false
        }
        // If no active rules and caffeination is user-initiated, leave it alone
    }

    // MARK: - Private Helpers

    /// Ensures the schedule evaluation timer is running.
    ///
    /// Creates a repeating timer that fires every 60 seconds to check
    /// if any schedule rule should activate or deactivate.
    private func ensureScheduleTimerRunning() {
        // Don't create a duplicate timer
        guard scheduleTimer == nil else { return }
        // Create a repeating timer that evaluates schedules every minute
        scheduleTimer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true
        ) { [weak self] _ in
            // Re-evaluate all schedule rules
            self?.evaluateSchedules()
        }
    }
}
