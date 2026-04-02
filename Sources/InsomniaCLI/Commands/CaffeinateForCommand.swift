// CaffeinateForCommand.swift — InsomniaCLI
//
// Implements the `insomnia for <duration>` subcommand for timed caffeination.
// Parses human-readable duration strings (e.g., "30m", "2h", "1h30m", "90s")
// using DurationOption.parse(). Supports both IPC and standalone modes.

import ArgumentParser
import Foundation
import InsomniaCore

/// Starts timed caffeination for a specified duration.
///
/// Accepts a human-readable duration string and prevents sleep for that
/// period. When the duration expires, caffeination stops automatically.
/// Supports standalone mode when the GUI is not running.
struct CaffeinateForCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "for",
        // Description shown in help output
        abstract: "Caffeinate for a specific duration (e.g., 30m, 2h, 1h30m)"
    )

    // MARK: - Arguments

    /// The duration string to parse (e.g., "30m", "2h", "1h30m", "90s").
    ///
    /// Parsed by `DurationOption.parse()` which supports combinations of
    /// hours (h), minutes (m), and seconds (s).
    @Argument(help: "Duration to caffeinate (e.g., 30m, 2h, 1h30m, 90s)")
    var duration: String

    /// When set, also prevents display sleep in addition to system sleep.
    @Flag(name: .long, help: "Also prevent display sleep")
    var display: Bool = false

    // MARK: - Execution

    /// Runs the caffeinate-for command.
    ///
    /// Parses the duration string, then either sends the command via IPC
    /// to the GUI or enters standalone mode for the specified duration.
    mutating func run() throws {
        // Parse the user-provided duration string into a DurationOption
        let durationOption = try DurationOption.parse(duration)

        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send caffeinateFor command via IPC
            let response = try client.send(.caffeinateFor(seconds: durationOption.timeInterval))
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — enter standalone mode for the duration
            try runStandalone(duration: durationOption)
        }
    }

    // MARK: - Standalone Mode

    /// Runs in standalone mode for the specified duration.
    ///
    /// Creates a PowerAssertionManager, starts a timed power assertion,
    /// installs a SIGINT handler for early exit, and blocks on the run loop
    /// until the duration expires.
    ///
    /// - Parameter duration: The parsed duration option specifying how long to caffeinate.
    private func runStandalone(duration: DurationOption) throws {
        // Determine the assertion type based on the --display flag
        let assertionType: PowerAssertionType = display
            ? .preventUserIdleDisplaySleep
            : .preventUserIdleSystemSleep

        // Create the power assertion manager with real IOKit provider
        let manager = PowerAssertionManager()
        // Start the timed caffeination assertion
        try manager.caffeinate(for: duration.timeInterval, type: assertionType)

        // Display the standalone mode banner with current state
        CLIOutput.printStandalone(state: manager.state)

        // Install SIGINT (Ctrl+C) handler for early clean shutdown
        signal(SIGINT) { _ in
            // Print farewell message on early exit
            print("\nDecaffeinated. Goodbye! \u{1F344}")
            _Exit(0)
        }

        // Calculate the expiry date from the duration
        let expiryDate = Date().addingTimeInterval(duration.timeInterval)
        // Block the main thread until the duration expires.
        // RunLoop.current.run(until:) returns when the date is reached.
        RunLoop.current.run(until: expiryDate)

        // Duration expired — clean up and exit
        try manager.decaffeinate()
        print("Duration expired. Decaffeinated. Goodbye! \u{1F344}")
    }
}
