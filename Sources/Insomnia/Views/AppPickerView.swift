// AppPickerView.swift — Insomnia GUI
//
// Lists currently running applications for the "Caffeinate While..." feature.
// The user selects an app to start caffeination that lasts until that app
// terminates. Queries AppWatcher.runningApplications() for the app list.

import SwiftUI
import InsomniaCore

/// A window view listing running applications for app-watching caffeination.
///
/// Displays each running application with its name and bundle identifier.
/// Tapping an app starts caffeination that automatically ends when the
/// selected app quits.
struct AppPickerView: View {
    // MARK: - Dependencies

    /// The view model to call when the user selects an app.
    var viewModel: MenuBarViewModel

    /// Environment dismiss action to close the window after selection.
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// The list of currently running applications, loaded on appear.
    @State private var apps: [(name: String, bundleIdentifier: String)] = []

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Window title
            Text("Caffeinate While Running")
                .font(.headline)
                .padding()

            // Scrollable list of running applications
            List(apps, id: \.bundleIdentifier) { app in
                Button {
                    // Start caffeination while this app is running
                    viewModel.caffeinateWhile(
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.name
                    )
                    // Close the picker after selection
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        // App display name
                        Text(app.name)
                            .font(.body)
                        // Bundle identifier as secondary info
                        Text(app.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 350, height: 400)
        .onAppear {
            // Load the running applications list when the view appears
            apps = AppWatcher.runningApplications()
        }
    }
}
