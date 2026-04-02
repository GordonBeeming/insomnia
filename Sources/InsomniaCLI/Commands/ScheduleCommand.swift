// ScheduleCommand.swift — InsomniaCLI
//
// Implements the `insomnia schedule` subcommand group for managing
// recurring caffeination schedules. Provides list, add, and remove
// subcommands. All schedule operations require the GUI to be running
// since schedules are persisted and managed by the app.

import ArgumentParser
import Foundation
import InsomniaCore

/// Parent command for schedule management subcommands.
///
/// Provides subcommands to list, add, and remove schedule rules
/// for automatic caffeination. All operations require the GUI
/// application to be running.
struct ScheduleCommand: ParsableCommand {
    /// Command configuration for help text, command name, and subcommands.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "schedule",
        // Description shown in help output
        abstract: "Manage caffeination schedules",
        // Register the schedule subcommands
        subcommands: [
            ListSchedulesCommand.self,
            AddScheduleCommand.self,
            RemoveScheduleCommand.self,
        ],
        // Default to listing schedules when no subcommand is specified
        defaultSubcommand: ListSchedulesCommand.self
    )
}

// MARK: - List Schedules

/// Lists all configured caffeination schedules.
///
/// Queries the GUI via IPC for the current list of schedule rules
/// and displays them with their enabled/disabled status.
struct ListSchedulesCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "list",
        // Description shown in help output
        abstract: "List all caffeination schedules"
    )

    // MARK: - Execution

    /// Runs the schedule list command.
    ///
    /// Sends a listSchedules command via IPC and displays the results.
    /// Requires the GUI to be running since schedules are managed by the app.
    mutating func run() throws {
        // Create an IPC client to check GUI status
        let client = IPCClient()

        // Verify the GUI is running before querying schedules
        guard client.isGUIRunning else {
            CLIOutput.printError("Insomnia.app is not running. Schedules are managed by the app.")
            return
        }

        // Send the list schedules command via IPC
        let response = try client.send(.listSchedules)
        // Display the formatted schedule list
        CLIOutput.printResponse(response)
    }
}

// MARK: - Add Schedule

/// Adds a new caffeination schedule rule.
///
/// Creates a schedule rule with the specified weekdays, start time,
/// and end time. The schedule will automatically activate caffeination
/// during the configured time windows.
struct AddScheduleCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "add",
        // Description shown in help output
        abstract: "Add a new caffeination schedule"
    )

    // MARK: - Options

    /// Comma-separated list of weekday abbreviations.
    ///
    /// Accepts standard three-letter abbreviations: mon, tue, wed, thu, fri, sat, sun.
    /// Example: "mon,tue,wed,thu,fri" for weekdays only.
    @Option(name: .long, help: "Comma-separated weekdays (mon,tue,wed,thu,fri,sat,sun)")
    var weekdays: String

    /// The start time for the caffeination window in HH:mm format.
    @Option(name: .long, help: "Start time (HH:mm)")
    var start: String

    /// The end time for the caffeination window in HH:mm format.
    @Option(name: .long, help: "End time (HH:mm)")
    var end: String

    // MARK: - Execution

    /// Runs the add schedule command.
    ///
    /// Parses the weekdays and times, builds a ScheduleRule, and sends
    /// it to the GUI via IPC for persistent storage.
    mutating func run() throws {
        // Create an IPC client to check GUI status
        let client = IPCClient()

        // Verify the GUI is running before adding schedules
        guard client.isGUIRunning else {
            CLIOutput.printError("Insomnia.app is not running. Schedules are managed by the app.")
            return
        }

        // Parse the weekdays from the comma-separated string
        let parsedWeekdays = try parseWeekdays(weekdays)
        // Parse the start and end times from HH:mm strings
        let startTime = try parseTimeComponents(start)
        let endTime = try parseTimeComponents(end)

        // Build the schedule rule with parsed parameters
        let rule = ScheduleRule(
            weekdays: parsedWeekdays,
            startTime: startTime,
            endTime: endTime
        )

        // Send the add schedule command via IPC
        let response = try client.send(.addSchedule(rule))
        // Display the formatted response
        CLIOutput.printResponse(response)
    }

    // MARK: - Parsing Helpers

    /// Parses a comma-separated weekday string into a Set of Weekday values.
    ///
    /// Accepts three-letter abbreviations (case-insensitive):
    /// mon, tue, wed, thu, fri, sat, sun.
    ///
    /// - Parameter input: The comma-separated weekday string.
    /// - Returns: A Set of parsed Weekday values.
    /// - Throws: `ValidationError` if any weekday abbreviation is invalid.
    private func parseWeekdays(_ input: String) throws -> Set<Weekday> {
        // Split on commas and trim whitespace from each component
        let parts = input.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var result = Set<Weekday>()

        // Map each abbreviation to its Weekday enum case
        for part in parts {
            switch part {
            case "sun": result.insert(.sunday)
            case "mon": result.insert(.monday)
            case "tue": result.insert(.tuesday)
            case "wed": result.insert(.wednesday)
            case "thu": result.insert(.thursday)
            case "fri": result.insert(.friday)
            case "sat": result.insert(.saturday)
            default:
                // Invalid abbreviation — throw with guidance
                throw ValidationError("Invalid weekday '\(part)'. Use: mon, tue, wed, thu, fri, sat, sun")
            }
        }

        // Must have at least one weekday
        guard !result.isEmpty else {
            throw ValidationError("At least one weekday is required")
        }

        return result
    }

    /// Parses a time string in HH:mm format into DateComponents.
    ///
    /// Extracts hour and minute values and validates their ranges.
    ///
    /// - Parameter timeString: The time string to parse.
    /// - Returns: DateComponents with hour and minute set.
    /// - Throws: `ValidationError` if the format is invalid.
    private func parseTimeComponents(_ timeString: String) throws -> DateComponents {
        // Split on colon separator
        let parts = timeString.split(separator: ":")
        // Validate format: exactly two numeric components in valid ranges
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else {
            throw ValidationError("Invalid time format '\(timeString)'. Use HH:mm (e.g., 09:00, 17:00)")
        }
        // Build DateComponents with the parsed hour and minute
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }
}

// MARK: - Remove Schedule

/// Removes a schedule rule by its UUID.
///
/// Takes a UUID string identifying the schedule rule to remove.
/// The short UUID prefix shown in `schedule list` output can be used
/// if it uniquely identifies the rule.
struct RemoveScheduleCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "remove",
        // Description shown in help output
        abstract: "Remove a schedule by UUID"
    )

    // MARK: - Arguments

    /// The UUID string of the schedule rule to remove.
    ///
    /// Must be a valid UUID string. Use `insomnia schedule list` to find
    /// the UUID of the schedule to remove.
    @Argument(help: "UUID of the schedule to remove")
    var id: String

    // MARK: - Execution

    /// Runs the remove schedule command.
    ///
    /// Validates the UUID, sends a removeSchedule command via IPC,
    /// and displays the result.
    mutating func run() throws {
        // Create an IPC client to check GUI status
        let client = IPCClient()

        // Verify the GUI is running before removing schedules
        guard client.isGUIRunning else {
            CLIOutput.printError("Insomnia.app is not running. Schedules are managed by the app.")
            return
        }

        // Validate the UUID string
        guard let uuid = UUID(uuidString: id) else {
            CLIOutput.printError("Invalid UUID: '\(id)'. Use `insomnia schedule list` to find schedule IDs.")
            return
        }

        // Send the remove schedule command via IPC
        let response = try client.send(.removeSchedule(id: uuid))
        // Display the formatted response
        CLIOutput.printResponse(response)
    }
}
