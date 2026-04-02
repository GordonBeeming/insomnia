// CaffeinateUntilCommand.swift — InsomniaCLI
//
// Implements the `insomnia until <time>` subcommand for caffeinating until
// a specific time of day. Parses time strings like "17:00" or "23:30".
// If the specified time has already passed today, targets tomorrow instead.

import ArgumentParser
import Foundation
import InsomniaCore

/// Starts caffeination until a specific time of day.
///
/// Accepts a time string in HH:mm format and prevents sleep until that
/// time is reached. If the time has already passed today, it targets
/// the same time tomorrow. Supports standalone mode.
struct CaffeinateUntilCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "until",
        // Description shown in help output
        abstract: "Caffeinate until a specific time (e.g., 17:00, 23:30)"
    )

    // MARK: - Arguments

    /// The target time string in HH:mm format (e.g., "17:00", "23:30").
    ///
    /// Parsed into today's date at that time. If the time has already
    /// passed today, the target becomes tomorrow at that time.
    @Argument(help: "Time to caffeinate until (e.g., 17:00, 23:30)")
    var time: String

    // MARK: - Execution

    /// Runs the caffeinate-until command.
    ///
    /// Parses the time string into a target Date, then either sends the
    /// command via IPC to the GUI or enters standalone mode.
    mutating func run() throws {
        // Parse the time string into a target date
        let targetDate = try parseTime(time)

        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send caffeinateUntil command via IPC
            let response = try client.send(.caffeinateUntil(date: targetDate))
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — enter standalone mode until the target time
            try runStandalone(until: targetDate)
        }
    }

    // MARK: - Time Parsing

    /// Parses a time string in HH:mm format into a Date.
    ///
    /// Creates a Date for today at the specified time. If that time has
    /// already passed, advances to tomorrow at the same time.
    ///
    /// - Parameter timeString: The time string to parse (e.g., "17:00").
    /// - Returns: A Date representing the next occurrence of that time.
    /// - Throws: `ValidationError` if the time string cannot be parsed.
    private func parseTime(_ timeString: String) throws -> Date {
        // Split the time string on the colon separator
        let parts = timeString.split(separator: ":")
        // Validate that we have exactly two components (hour and minute)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              hour >= 0, hour < 24,
              minute >= 0, minute < 60 else {
            // Invalid format — throw a validation error with usage guidance
            throw ValidationError("Invalid time format '\(timeString)'. Use HH:mm (e.g., 17:00, 23:30)")
        }

        // Build a date for today at the specified time
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        // Set the parsed hour and minute
        components.hour = hour
        components.minute = minute
        components.second = 0

        // Create the date from the components
        guard var targetDate = calendar.date(from: components) else {
            throw ValidationError("Could not create date for time '\(timeString)'")
        }

        // If the time has already passed today, advance to tomorrow
        if targetDate <= Date() {
            // Add one day to get tomorrow at the same time
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: targetDate) else {
                throw ValidationError("Could not calculate tomorrow's date")
            }
            targetDate = tomorrow
        }

        return targetDate
    }

    // MARK: - Standalone Mode

    /// Runs in standalone mode until the specified date.
    ///
    /// Creates a PowerAssertionManager, starts a timed power assertion,
    /// installs a SIGINT handler, and blocks until the target time.
    ///
    /// - Parameter date: The target date at which caffeination should end.
    private func runStandalone(until date: Date) throws {
        // Create the power assertion manager with real IOKit provider
        let manager = PowerAssertionManager()
        // Start the timed caffeination assertion until the target date
        try manager.caffeinate(until: date, type: .preventUserIdleSystemSleep)

        // Display the standalone mode banner with current state
        CLIOutput.printStandalone(state: manager.state)

        // Install SIGINT (Ctrl+C) handler for early clean shutdown
        signal(SIGINT) { _ in
            print("\nDecaffeinated. Goodbye! \u{1F344}")
            _Exit(0)
        }

        // Block the main thread until the target time.
        // RunLoop.current.run(until:) returns when the date is reached.
        RunLoop.current.run(until: date)

        // Target time reached — clean up and exit
        try manager.decaffeinate()
        print("Time reached. Decaffeinated. Goodbye! \u{1F344}")
    }
}
