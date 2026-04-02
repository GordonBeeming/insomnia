// StatusItemController.swift — Insomnia GUI
//
// Provides helper logic for computing the menu bar icon appearance based
// on the current PowerState, icon style preference, and remaining-time
// display setting. The actual MenuBarExtra label is rendered by SwiftUI,
// but this controller encapsulates the icon selection logic.

import Foundation
import InsomniaCore

/// Computes the appropriate menu bar icon and optional time label
/// based on the current state and user preferences.
///
/// The MenuBarExtra scene in ``InsomniaApp`` uses these computed values
/// to render the label. This controller isolates the icon-selection logic
/// so it can be tested and reused independently.
struct StatusItemController {
    // MARK: - Icon Selection

    /// Returns the SF Symbol name for the menu bar icon based on state and style.
    ///
    /// Each icon style uses a different pair of SF Symbols:
    /// - **default**: Coffee cup (awake) / Moon with zzz (sleep)
    /// - **minimal**: Filled circle (awake) / Empty circle (sleep)
    /// - **dapple**: Leaf/mushroom-like symbol (awake) / Leaf (sleep)
    ///
    /// - Parameters:
    ///   - state: The current caffeination power state.
    ///   - style: The user's preferred icon style from settings.
    /// - Returns: An SF Symbols name string suitable for `Image(systemName:)`.
    static func iconName(for state: PowerState, style: IconStyle) -> String {
        switch style {
        case .default:
            // Coffee cup theme — the classic caffeinate metaphor
            return state.isActive ? "cup.and.saucer.fill" : "moon.zzz"
        case .minimal:
            // Simple dot — unobtrusive, blends with other menu bar icons
            return state.isActive ? "circle.fill" : "circle"
        case .dapple:
            // Mushroom-inspired — nods to the Dapple mascot
            return state.isActive ? "leaf.fill" : "leaf"
        }
    }

    /// Returns an optional time string to display alongside the menu bar icon.
    ///
    /// Only returns a value when `showTime` is `true` and the state has a
    /// remaining-time component (i.e., timed caffeination).
    ///
    /// - Parameters:
    ///   - state: The current caffeination power state.
    ///   - showTime: Whether the user wants remaining time shown in the menu bar.
    /// - Returns: A formatted time string, or `nil` if not applicable.
    static func timeLabel(for state: PowerState, showTime: Bool) -> String? {
        // Only show time if the user has enabled the preference
        guard showTime else { return nil }
        // Only timed states have remaining time
        return state.remainingDescription
    }
}
