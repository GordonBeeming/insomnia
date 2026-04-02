// ScheduleEditorView.swift — Insomnia GUI
//
// CRUD interface for managing recurring caffeination schedule rules.
// Lists existing rules with enable/disable toggles, provides an inline
// form for adding new rules, and supports deletion. Binds directly to
// the CaffeinationScheduler's scheduleRules array.

import SwiftUI
import InsomniaCore

/// A window view for creating, editing, and deleting schedule rules.
///
/// Displays a list of existing ``ScheduleRule`` entries with toggle switches
/// and delete buttons, plus a form section for adding new rules with weekday
/// selection and start/end time pickers.
struct ScheduleEditorView: View {
    // MARK: - Dependencies

    /// The view model providing access to the scheduler.
    var viewModel: MenuBarViewModel

    // MARK: - New Rule State

    /// Selected weekdays for the new rule being composed.
    @State private var selectedWeekdays: Set<Weekday> = []

    /// Start hour for the new rule (0–23).
    @State private var startHour: Int = 9

    /// Start minute for the new rule (0–59).
    @State private var startMinute: Int = 0

    /// End hour for the new rule (0–23).
    @State private var endHour: Int = 17

    /// End minute for the new rule (0–59).
    @State private var endMinute: Int = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Window title
            Text("Schedules")
                .font(.headline)
                .padding()

            // Existing rules list
            existingRulesList

            Divider()

            // New rule form
            newRuleForm
        }
        .frame(width: 500, height: 500)
    }

    // MARK: - Existing Rules List

    /// Scrollable list of existing schedule rules with toggle and delete controls.
    private var existingRulesList: some View {
        List {
            if viewModel.scheduler.scheduleRules.isEmpty {
                // Empty state message when no rules exist
                Text("No schedules configured")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Render each rule with its summary, toggle, and delete button
                ForEach(viewModel.scheduler.scheduleRules) { rule in
                    HStack {
                        // Rule summary text (e.g., "Mon, Wed 09:00–17:00")
                        VStack(alignment: .leading) {
                            Text(rule.displaySummary)
                                .font(.body)
                            Text(rule.isEnabled ? "Enabled" : "Disabled")
                                .font(.caption)
                                .foregroundStyle(rule.isEnabled ? .green : .secondary)
                        }

                        Spacer()

                        // Delete button to remove this rule
                        Button(role: .destructive) {
                            viewModel.scheduler.removeScheduleRule(id: rule.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    // MARK: - New Rule Form

    /// Inline form for composing and adding a new schedule rule.
    private var newRuleForm: some View {
        VStack(spacing: 12) {
            Text("Add Schedule")
                .font(.subheadline)
                .fontWeight(.semibold)

            // Weekday selection — horizontal row of toggle buttons
            HStack(spacing: 4) {
                ForEach(Weekday.allCases, id: \.self) { day in
                    Button(day.shortName) {
                        // Toggle the weekday selection
                        if selectedWeekdays.contains(day) {
                            selectedWeekdays.remove(day)
                        } else {
                            selectedWeekdays.insert(day)
                        }
                    }
                    .buttonStyle(.bordered)
                    // Highlight selected days with accent tint
                    .tint(selectedWeekdays.contains(day) ? .accentColor : .secondary)
                }
            }

            // Time range pickers for start and end
            HStack {
                // Start time pickers
                VStack {
                    Text("Start")
                        .font(.caption)
                    HStack(spacing: 2) {
                        // Hour stepper
                        Stepper(value: $startHour, in: 0...23) {
                            Text(String(format: "%02d", startHour))
                        }
                        Text(":")
                        // Minute stepper
                        Stepper(value: $startMinute, in: 0...59) {
                            Text(String(format: "%02d", startMinute))
                        }
                    }
                }

                Spacer()

                // End time pickers
                VStack {
                    Text("End")
                        .font(.caption)
                    HStack(spacing: 2) {
                        Stepper(value: $endHour, in: 0...23) {
                            Text(String(format: "%02d", endHour))
                        }
                        Text(":")
                        Stepper(value: $endMinute, in: 0...59) {
                            Text(String(format: "%02d", endMinute))
                        }
                    }
                }
            }

            // Add button — disabled when no weekdays are selected
            Button("Add Schedule") {
                // Build the new schedule rule from the form state
                let rule = ScheduleRule(
                    weekdays: selectedWeekdays,
                    startTime: DateComponents(hour: startHour, minute: startMinute),
                    endTime: DateComponents(hour: endHour, minute: endMinute)
                )
                // Add to the scheduler
                viewModel.scheduler.addScheduleRule(rule)
                // Reset the form for the next entry
                selectedWeekdays = []
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedWeekdays.isEmpty)
        }
        .padding()
    }
}
