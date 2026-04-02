// DurationPickerView.swift — Insomnia GUI
//
// Custom duration input for the "Caffeinate For... > Custom..." menu action.
// Provides hours and minutes steppers with a Start button. Presented in its
// own window since MenuBarExtra with `.menu` style cannot host interactive
// controls like steppers.

import SwiftUI
import InsomniaCore

/// A window view for entering a custom caffeination duration.
///
/// Provides numeric steppers for hours (0–24) and minutes (0–59),
/// then starts timed caffeination via the shared ``MenuBarViewModel``.
struct DurationPickerView: View {
    // MARK: - State

    /// The number of hours for the custom duration.
    @State private var hours: Int = 1

    /// The number of minutes for the custom duration.
    @State private var minutes: Int = 0

    /// The view model to call when the user starts caffeination.
    var viewModel: MenuBarViewModel

    /// Environment dismiss action to close the window after starting.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 20) {
            // Title explaining the purpose of this dialog
            Text("Custom Duration")
                .font(.headline)

            // Hours and minutes input fields
            HStack(spacing: 16) {
                // Hours stepper with label
                VStack {
                    Text("Hours")
                        .font(.caption)
                    Stepper(value: $hours, in: 0...24) {
                        Text("\(hours)")
                            .frame(width: 30, alignment: .center)
                    }
                }

                // Minutes stepper with label
                VStack {
                    Text("Minutes")
                        .font(.caption)
                    Stepper(value: $minutes, in: 0...59) {
                        Text("\(minutes)")
                            .frame(width: 30, alignment: .center)
                    }
                }
            }

            // Action buttons
            HStack {
                Button("Cancel") {
                    // Close without starting caffeination
                    dismiss()
                }

                Spacer()

                Button("Start") {
                    // Calculate total seconds from hours and minutes
                    let totalSeconds = TimeInterval(hours * 3600 + minutes * 60)
                    if totalSeconds > 0 {
                        // Start timed caffeination with the custom duration
                        viewModel.caffeinateFor(.custom(totalSeconds))
                    }
                    // Close the picker window
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                // Disable start when duration is zero
                .disabled(hours == 0 && minutes == 0)
            }
        }
        .padding(24)
        .frame(width: 280)
    }
}
