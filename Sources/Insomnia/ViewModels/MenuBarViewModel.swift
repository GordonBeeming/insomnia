// MenuBarViewModel.swift — Insomnia GUI
//
// Drives the menu bar UI by exposing reactive properties derived from the
// CaffeinationScheduler and InsomniaConfiguration. All caffeination actions
// flow through this view model so the views remain stateless and declarative.

import Foundation
import SwiftUI
import InsomniaCore

/// View model that powers the menu bar dropdown and status display.
///
/// Owns or references the shared ``CaffeinationScheduler`` and
/// ``InsomniaConfiguration``, exposing computed properties and action
/// methods that SwiftUI views bind to. Uses `@Observable` for automatic
/// view invalidation when state changes.
@Observable
final class MenuBarViewModel {
    // MARK: - Dependencies

    /// The scheduler that orchestrates all caffeination modes.
    /// Shared with the ``AppDelegate`` so IPC and GUI use the same instance.
    let scheduler: CaffeinationScheduler

    /// User preferences loaded from UserDefaults.
    let configuration: InsomniaConfiguration

    // MARK: - Initialization

    /// Creates a menu bar view model with the given scheduler and configuration.
    ///
    /// - Parameters:
    ///   - scheduler: The caffeination scheduler to use for all actions.
    ///   - configuration: The configuration providing user preferences.
    init(
        scheduler: CaffeinationScheduler = CaffeinationScheduler(),
        configuration: InsomniaConfiguration = InsomniaConfiguration()
    ) {
        self.scheduler = scheduler
        self.configuration = configuration
    }

    // MARK: - Computed Properties

    /// The current power state from the scheduler's power manager.
    var currentState: PowerState {
        // Delegate to the power manager for the authoritative state
        scheduler.powerManager.state
    }

    /// Whether caffeination is currently active in any mode.
    var isActive: Bool {
        // Convenience wrapper around the power state
        currentState.isActive
    }

    /// Human-readable status text for the menu bar dropdown header.
    ///
    /// Shows an emoji prefix and the state description, including remaining
    /// time when applicable.
    var statusText: String {
        switch currentState {
        case .decaffeinated:
            // Sleeping state with zzz emoji
            return "\u{1F4A4} Decaffeinated"
        case .caffeinatedIndefinitely:
            // Active state with coffee emoji
            return "\u{2615} Caffeinated"
        case .caffeinatedUntil:
            // Timed state — append remaining time if available
            if let remaining = currentState.remainingDescription {
                return "\u{2615} Caffeinated \u{2014} \(remaining)"
            }
            return "\u{2615} Caffeinated"
        case .caffeinatedWhileRunning(_, let appName):
            // App-watching state — show which app
            return "\u{2615} Caffeinated while \(appName) runs"
        }
    }

    /// The SF Symbol name for the menu bar icon based on current state and icon style.
    var menuBarImage: String {
        // Delegate to StatusItemController which respects the icon style preference
        StatusItemController.iconName(for: currentState, style: configuration.iconStyle)
    }

    // MARK: - Actions

    /// Starts indefinite caffeination using the user's preferred assertion type.
    func caffeinate() {
        do {
            try scheduler.powerManager.caffeinate(type: configuration.preferredAssertionType)
        } catch {
            // Log the error — the UI will reflect the unchanged state
            print("Failed to caffeinate: \(error.localizedDescription)")
        }
    }

    /// Stops all active caffeination and watches.
    func decaffeinate() {
        do {
            try scheduler.cancelAll()
        } catch {
            print("Failed to decaffeinate: \(error.localizedDescription)")
        }
    }

    /// Toggles between caffeinated and decaffeinated states.
    func toggle() {
        if isActive {
            decaffeinate()
        } else {
            caffeinate()
        }
    }

    /// Starts timed caffeination for the given duration option.
    ///
    /// - Parameter duration: The preset or custom duration to caffeinate for.
    func caffeinateFor(_ duration: DurationOption) {
        do {
            try scheduler.startTimed(duration, type: configuration.preferredAssertionType)
        } catch {
            print("Failed to caffeinate for duration: \(error.localizedDescription)")
        }
    }

    /// Starts timed caffeination until the specified date.
    ///
    /// - Parameter date: The date at which caffeination should automatically end.
    func caffeinateUntil(_ date: Date) {
        do {
            try scheduler.startUntil(date, type: configuration.preferredAssertionType)
        } catch {
            print("Failed to caffeinate until date: \(error.localizedDescription)")
        }
    }

    /// Starts caffeination that lasts while the specified app is running.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The bundle ID of the app to watch.
    ///   - appName: The display name of the app.
    func caffeinateWhile(bundleIdentifier: String, appName: String) {
        do {
            try scheduler.startWhileAppRunning(
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                type: configuration.preferredAssertionType
            )
        } catch {
            print("Failed to caffeinate while app running: \(error.localizedDescription)")
        }
    }
}
