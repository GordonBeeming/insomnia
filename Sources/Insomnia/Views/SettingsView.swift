// SettingsView.swift — Insomnia GUI
//
// Form-based settings window with sections for General and Appearance
// preferences. Binds to SettingsViewModel which wraps the
// InsomniaConfiguration and handles side effects.

import SwiftUI
import InsomniaCore

/// The settings window content, presented via the SwiftUI `Settings` scene.
///
/// Organized into two sections:
/// - **General**: Launch at login
/// - **Appearance**: Icon style, visibility, and remaining time display
struct SettingsView: View {
    // MARK: - Dependencies

    /// The settings view model providing bindable preference properties.
    @Bindable var viewModel: SettingsViewModel

    // MARK: - Body

    var body: some View {
        Form {
            // General application behavior settings
            generalSection

            // Visual appearance preferences
            appearanceSection
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 300)
    }

    // MARK: - General Section

    /// Settings for app startup behavior.
    private var generalSection: some View {
        Section("General") {
            // Toggle for automatic launch at system login
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
        }
    }

    // MARK: - Appearance Section

    /// Settings for menu bar appearance and information display.
    private var appearanceSection: some View {
        Section("Appearance") {
            // Toggle to hide the icon when not caffeinated
            Toggle("Hide icon when decaffeinated", isOn: $viewModel.hideIconWhenDecaffeinated)

            // Toggle to show countdown in the menu bar title
            Toggle("Show remaining time in menu bar", isOn: $viewModel.showRemainingTimeInMenuBar)
        }
    }
}
