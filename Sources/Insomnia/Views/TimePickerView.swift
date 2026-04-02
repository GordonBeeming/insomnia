// TimePickerView.swift — Insomnia GUI
//
// Time picker for the "Caffeinate Until..." menu action. Lets the user
// select a target time via a DatePicker in hourAndMinute mode, displays
// how long until that time, and starts caffeination on confirmation.

import SwiftUI
import InsomniaCore

/// A window view for selecting a target time to caffeinate until.
///
/// Uses a `DatePicker` in `.hourAndMinute` mode and shows the
/// duration until the selected time. The user confirms with a Start button.
struct TimePickerView: View {
    // MARK: - State

    /// The selected target date/time, initialized to one hour from now.
    @State private var targetDate: Date = Date().addingTimeInterval(3600)

    /// The view model to call when the user starts caffeination.
    var viewModel: MenuBarViewModel

    /// Environment dismiss action to close the window after starting.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // Title explaining the purpose of this dialog
            Text("Caffeinate Until")
                .font(.headline)

            // Time picker restricted to hour and minute selection
            DatePicker(
                "Target time",
                selection: $targetDate,
                // Restrict to future times only
                in: Date()...,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.field)

            // Display the duration until the selected time
            Text(durationDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Start") {
                    // Start caffeination until the selected time
                    viewModel.caffeinateUntil(targetDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }

    // MARK: - Helpers

    /// A human-readable description of the time remaining until the target date.
    private var durationDescription: String {
        let interval = targetDate.timeIntervalSinceNow
        // Guard against negative intervals (shouldn't happen with date range)
        guard interval > 0 else { return "Select a future time" }
        // Calculate hours and minutes from the interval
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m from now"
        }
        return "\(minutes)m from now"
    }
}
