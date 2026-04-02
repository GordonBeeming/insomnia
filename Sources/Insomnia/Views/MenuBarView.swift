// MenuBarView.swift — Insomnia GUI
//
// The primary menu content displayed in the MenuBarExtra dropdown. Renders
// the caffeination status, toggle controls, timed/app-watching submenus,
// and links to settings, about, and quit actions. Uses standard SwiftUI
// menu items compatible with MenuBarExtra's `.menu` rendering style.

import SwiftUI
import InsomniaCore

/// The main dropdown menu shown when the user clicks the menu bar icon.
///
/// Structured as a flat list of ``Button``, ``Menu`` (submenu), and ``Divider``
/// items. The `.menu` style of ``MenuBarExtra`` requires standard menu-compatible
/// views — no custom layouts or interactive controls.
struct MenuBarView: View {
    // MARK: - Dependencies

    /// The view model driving all state and actions.
    @Bindable var viewModel: MenuBarViewModel

    /// Environment action to open named windows (About, Duration Picker, etc.).
    @Environment(\.openWindow) private var openWindow

    // MARK: - Body

    var body: some View {
        // Status text at the top of the menu
        statusSection

        Divider()

        // Primary toggle button — caffeinate or decaffeinate
        toggleSection

        // Timed caffeination submenu
        caffeinateForMenu

        // Caffeinate until a specific time
        caffeinateUntilButton

        // App-watching submenu
        caffeinateWhileMenu

        Divider()

        // Schedule editor link
        Button("Schedules...") {
            // Open the schedule editor as a separate window and bring to front
            openWindow(id: "schedules")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        // Settings, About, and Quit
        footerSection
    }

    // MARK: - Status Section

    /// Displays the current caffeination status as a disabled menu item.
    private var statusSection: some View {
        // Show the status text from the view model (includes emoji)
        Text(viewModel.statusText)
    }

    // MARK: - Toggle Section

    /// A button that toggles between caffeinate and decaffeinate.
    private var toggleSection: some View {
        Button(viewModel.isActive ? "Decaffeinate" : "Caffeinate") {
            // Toggle the caffeination state
            viewModel.toggle()
        }
    }

    // MARK: - Caffeinate For Submenu

    /// Submenu with preset duration options and a custom duration entry.
    private var caffeinateForMenu: some View {
        Menu("Caffeinate For...") {
            // Preset duration buttons
            Button("15 Minutes") {
                viewModel.caffeinateFor(.fifteenMinutes)
            }
            Button("30 Minutes") {
                viewModel.caffeinateFor(.thirtyMinutes)
            }
            Button("1 Hour") {
                viewModel.caffeinateFor(.oneHour)
            }
            Button("2 Hours") {
                viewModel.caffeinateFor(.twoHours)
            }

            Divider()

            // Custom duration opens a separate input window
            Button("Custom...") {
                openWindow(id: "duration-picker")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - Caffeinate Until Button

    /// Opens a time picker window for "caffeinate until" functionality.
    private var caffeinateUntilButton: some View {
        Button("Caffeinate Until...") {
            // Open the time picker as a separate window and bring to front
            openWindow(id: "time-picker")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Caffeinate While Submenu

    /// Submenu listing currently running applications for app-watching mode.
    private var caffeinateWhileMenu: some View {
        Menu("Caffeinate While...") {
            // Query running apps from the AppWatcher utility
            let apps = AppWatcher.runningApplications()
            if apps.isEmpty {
                // No apps detected — show a placeholder
                Text("No applications found")
            } else {
                // List each running app as a selectable menu item
                ForEach(apps, id: \.bundleIdentifier) { app in
                    Button("\(app.name) (\(app.bundleIdentifier))") {
                        // Start caffeination while this app is running
                        viewModel.caffeinateWhile(
                            bundleIdentifier: app.bundleIdentifier,
                            appName: app.name
                        )
                    }
                }
            }
        }
    }

    // MARK: - Footer Section

    /// Settings, About, and Quit menu items.
    private var footerSection: some View {
        Group {
            Button("Settings...") {
                // Open the SwiftUI Settings scene via NSApp (compatible with all macOS 14+ SDKs)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                // Bring the app to the front so Settings isn't hidden behind other windows
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("About Insomnia") {
                // Open the about window and bring to front
                openWindow(id: "about")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit Insomnia") {
                // Terminate the application
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
