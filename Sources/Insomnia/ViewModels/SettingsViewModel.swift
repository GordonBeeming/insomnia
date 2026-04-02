// SettingsViewModel.swift — Insomnia GUI
//
// Bridges the InsomniaConfiguration to SwiftUI settings views by exposing
// bindable properties and handling side effects like dock icon visibility
// and launch-at-login registration via SMAppService.

import Foundation
import SwiftUI
import InsomniaCore
#if canImport(ServiceManagement)
import ServiceManagement
#endif

/// View model for the Settings window, binding user preferences to the UI.
///
/// Wraps ``InsomniaConfiguration`` and adds side-effect handling for settings
/// that require AppKit or ServiceManagement calls (dock icon visibility,
/// launch at login). Uses `@Observable` for SwiftUI integration.
@Observable
final class SettingsViewModel {
    // MARK: - Dependencies

    /// The configuration model that persists preferences to UserDefaults.
    let configuration: InsomniaConfiguration

    // MARK: - Initialization

    /// Creates a settings view model backed by the given configuration.
    ///
    /// - Parameter configuration: The configuration to bind to. Defaults to a new instance.
    init(configuration: InsomniaConfiguration = InsomniaConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - General Settings

    /// Whether the app should launch at system login.
    ///
    /// Setting this registers or unregisters the app with SMAppService.
    var launchAtLogin: Bool {
        get { configuration.launchAtLogin }
        set {
            configuration.launchAtLogin = newValue
            // Register or unregister with the system login items service
            updateLaunchAtLogin(newValue)
        }
    }

    /// Whether to prevent display sleep (in addition to system sleep).
    var preventDisplaySleep: Bool {
        get { configuration.preventDisplaySleep }
        set { configuration.preventDisplaySleep = newValue }
    }

    // MARK: - Appearance Settings

    /// The visual style of the menu bar icon.
    var iconStyle: IconStyle {
        get { configuration.iconStyle }
        set { configuration.iconStyle = newValue }
    }

    /// Whether to hide the menu bar icon when decaffeinated.
    var hideIconWhenDecaffeinated: Bool {
        get { configuration.hideIconWhenDecaffeinated }
        set { configuration.hideIconWhenDecaffeinated = newValue }
    }

    /// Whether to show remaining time in the menu bar title.
    var showRemainingTimeInMenuBar: Bool {
        get { configuration.showRemainingTimeInMenuBar }
        set { configuration.showRemainingTimeInMenuBar = newValue }
    }

    // MARK: - Dock Icon

    /// Whether the dock icon is visible.
    /// The actual activation policy change is deferred to when Settings closes
    /// (via onDisappear) to avoid hiding the settings window mid-interaction.
    var showDockIcon: Bool = false

    // MARK: - Public Helpers

    /// Applies the dock icon visibility setting by changing the activation policy.
    /// Called when the settings window closes, not on every toggle change.
    func applyDockIconVisibility() {
        if showDockIcon {
            NSApp.setActivationPolicy(.regular)
            // Reapply the custom icon since macOS resets it on policy change
            (NSApp.delegate as? AppDelegate)?.reapplyAppIcon()
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Registers or unregisters the app for launch at login via SMAppService.
    ///
    /// - Parameter enabled: Whether to enable launch at login.
    private func updateLaunchAtLogin(_ enabled: Bool) {
        #if canImport(ServiceManagement)
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    // Register with the system to launch at login
                    try SMAppService.mainApp.register()
                } else {
                    // Unregister from launch at login
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
