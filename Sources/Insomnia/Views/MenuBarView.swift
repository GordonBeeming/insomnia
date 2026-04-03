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

    /// The update checker for showing update status and triggering checks.
    var updateChecker: UpdateChecker

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
            activateAndOpen(windowId: "schedules")
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
                activateAndOpen(windowId: "duration-picker")
            }
        }
    }

    // MARK: - Caffeinate Until Button

    /// Opens a time picker window for "caffeinate until" functionality.
    private var caffeinateUntilButton: some View {
        Button("Caffeinate Until...") {
            activateAndOpen(windowId: "time-picker")
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

    /// Settings, About, Update, and Quit menu items.
    private var footerSection: some View {
        Group {
            Button("Settings...") {
                activateAndOpen(windowId: "settings")
            }

            Button("About \(BuildEnvironment.appName)") {
                activateAndOpen(windowId: "about")
            }

            Divider()

            // Update section — shows contextual status and actions
            updateSection

            Divider()

            Button("Quit \(BuildEnvironment.appName)") {
                // Terminate the application
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Update Section

    /// Update check status and action buttons.
    @ViewBuilder
    private var updateSection: some View {
        if updateChecker.isUpdateAvailable, let version = updateChecker.latestVersion {
            // An update is available — show download or release link
            if updateChecker.isDownloading {
                Text("Downloading v\(version)...")
            } else if updateChecker.downloadURL != nil {
                // DMG available — offer direct download
                Button("Download v\(version)") {
                    Task { await updateChecker.downloadAndInstall() }
                }
            } else {
                // Update exists but no DMG asset — show version info only
                Text("v\(version) available on GitHub")
            }
        }
        // Show error from the last check or download, if any
        if let error = updateChecker.lastError {
            Text(error)
        }
        if updateChecker.isChecking {
            // A check is in progress
            Text("Checking for updates...")
        } else {
            // Manual check button
            Button("Check for Updates") {
                Task { await updateChecker.checkForUpdate(force: true) }
            }
        }
    }

    // MARK: - Helpers

    /// Opens a window and activates the app so the window appears in front.
    /// The app stays in accessory mode (no dock icon) since LSUIElement is set.
    private func activateAndOpen(windowId: String) {
        openWindow(id: windowId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
