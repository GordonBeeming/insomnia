// InsomniaApp.swift — Insomnia GUI
//
// The @main entry point for the Insomnia macOS application. Configures a
// MenuBarExtra as the primary UI (menu bar icon with dropdown), a Settings
// scene for preferences, and auxiliary windows for the about dialog,
// duration picker, time picker, and schedule editor.

import SwiftUI
import InsomniaCore

/// The main application struct for Insomnia.
///
/// Uses `@NSApplicationDelegateAdaptor` to connect the ``AppDelegate`` for
/// lifecycle management. The primary UI is a ``MenuBarExtra`` with `.menu`
/// style that shows a dropdown menu when the user clicks the menu bar icon.
@main
struct InsomniaApp: App {
    // MARK: - Lifecycle

    /// The application delegate adaptor for managing startup, shutdown, and IPC.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - State

    /// The view model driving the menu bar UI, created from the delegate's scheduler.
    @State private var viewModel: MenuBarViewModel?

    // MARK: - Body

    var body: some Scene {
        // Primary UI — menu bar icon with dropdown menu
        MenuBarExtra {
            // Render the menu content if the view model is ready
            if let viewModel {
                MenuBarView(viewModel: viewModel)
            }
        } label: {
            // Menu bar icon changes based on caffeination state
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)

        // Settings window opened via "Settings..." menu item
        Settings {
            if let viewModel {
                SettingsView(viewModel: SettingsViewModel(configuration: viewModel.configuration))
            }
        }

        // About dialog window — uses BuildEnvironment for variant-aware title
        Window("About \(BuildEnvironment.appName)", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        // Custom duration picker window
        Window("Custom Duration", id: "duration-picker") {
            if let viewModel {
                DurationPickerView(viewModel: viewModel)
            }
        }
        .windowResizability(.contentSize)

        // Time picker window for "Caffeinate Until..."
        Window("Caffeinate Until", id: "time-picker") {
            if let viewModel {
                TimePickerView(viewModel: viewModel)
            }
        }
        .windowResizability(.contentSize)

        // Schedule editor window
        Window("Schedules", id: "schedules") {
            if let viewModel {
                ScheduleEditorView(viewModel: viewModel)
            }
        }
        .windowResizability(.contentSize)
    }

    // MARK: - Menu Bar Label

    /// The label displayed in the menu bar — an SF Symbol that changes
    /// based on the current caffeination state.
    @ViewBuilder
    private var menuBarLabel: some View {
        if let viewModel {
            // Show coffee cup when awake, moon when sleeping
            Image(systemName: viewModel.menuBarImage)
        } else {
            // Fallback icon before the view model initializes
            Image(systemName: "moon.zzz")
                .onAppear {
                    // Initialize the view model from the app delegate's scheduler
                    viewModel = MenuBarViewModel(
                        scheduler: appDelegate.scheduler,
                        configuration: appDelegate.configuration
                    )
                }
        }
    }
}
