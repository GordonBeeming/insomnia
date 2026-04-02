// SettingsView.swift — Insomnia GUI
//
// Form-based settings window with sections for General, Appearance, and
// Dock Icon preferences. Binds to SettingsViewModel which wraps the
// InsomniaConfiguration and handles side effects.

import SwiftUI
import InsomniaCore

/// The settings window content, presented via the SwiftUI `Settings` scene.
///
/// Organized into three sections:
/// - **General**: Launch at login and display sleep prevention
/// - **Appearance**: Icon style, visibility, and remaining time display
/// - **Dock Icon**: Toggle dock icon visibility
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

            // Dock icon visibility control
            dockIconSection
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
    }

    // MARK: - General Section

    /// Settings for app startup and sleep prevention mode.
    private var generalSection: some View {
        Section("General") {
            // Toggle for automatic launch at system login
            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)

            // Toggle for preventing display sleep vs. just system sleep
            Toggle("Prevent display sleep", isOn: $viewModel.preventDisplaySleep)
                .help("When enabled, prevents both display and system sleep. When disabled, only prevents system sleep.")
        }
    }

    // MARK: - Appearance Section

    /// Settings for menu bar icon style and information display.
    private var appearanceSection: some View {
        Section("Appearance") {
            // Icon style picker — default, minimal, or dapple
            Picker("Icon style", selection: $viewModel.iconStyle) {
                ForEach(IconStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }

            // Toggle to hide the icon when not caffeinated
            Toggle("Hide icon when decaffeinated", isOn: $viewModel.hideIconWhenDecaffeinated)

            // Toggle to show countdown in the menu bar title
            Toggle("Show remaining time in menu bar", isOn: $viewModel.showRemainingTimeInMenuBar)
        }
    }

    // MARK: - Dock Icon Section

    /// Settings for controlling dock icon visibility.
    private var dockIconSection: some View {
        Section("Dock Icon") {
            // Toggle between regular (visible) and accessory (hidden) activation policy
            Toggle("Show dock icon", isOn: $viewModel.showDockIcon)
                .help("When enabled, the app appears in the Dock. When disabled, it runs as a menu bar-only app.")
        }
    }
}
