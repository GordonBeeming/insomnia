// CaffeinateCommand.swift — InsomniaCLI
//
// Implements the `insomnia caffeinate` subcommand for starting indefinite
// caffeination. Supports a --display flag to also prevent display sleep.
// Operates in two modes: IPC mode (sends command to GUI) and standalone
// mode (manages power assertions directly when GUI is not running).

import ArgumentParser
import Foundation
import InsomniaCore

/// Starts indefinite caffeination, preventing the system from sleeping.
///
/// When the GUI application is running, sends a caffeinate command via IPC.
/// When the GUI is not running, enters standalone mode: creates a power
/// assertion directly and blocks until the user presses Ctrl+C.
struct CaffeinateCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "caffeinate",
        // Description shown in help output
        abstract: "Start indefinite caffeination"
    )

    // MARK: - Options

    /// When set, also prevents display sleep in addition to system sleep.
    ///
    /// Without this flag, only system sleep is prevented and the display
    /// may still turn off after the idle timeout.
    @Flag(name: .long, help: "Also prevent display sleep")
    var display: Bool = false

    // MARK: - Execution

    /// Runs the caffeinate command.
    ///
    /// Checks if the GUI is running via IPC socket connectivity.
    /// If running, sends the caffeinate command via IPC.
    /// If not running, enters standalone mode with direct power assertion management.
    mutating func run() throws {
        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send caffeinate command via IPC
            let response = try client.send(.caffeinate)
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — enter standalone mode
            try runStandalone()
        }
    }

    // MARK: - Standalone Mode

    /// Runs in standalone mode without the GUI application.
    ///
    /// Creates a PowerAssertionManager, starts an indefinite power assertion,
    /// installs a SIGINT handler for clean shutdown, and blocks on the run loop.
    private func runStandalone() throws {
        // Determine the assertion type based on the --display flag
        let assertionType: PowerAssertionType = display
            ? .preventUserIdleDisplaySleep
            : .preventUserIdleSystemSleep

        // Create the power assertion manager with real IOKit provider
        let manager = PowerAssertionManager()
        // Start the indefinite caffeination assertion
        try manager.caffeinate(type: assertionType)

        // Display the standalone mode banner with current state
        CLIOutput.printStandalone(state: manager.state)

        // Install SIGINT (Ctrl+C) handler for clean shutdown
        // When the user presses Ctrl+C, decaffeinate and exit gracefully
        signal(SIGINT) { _ in
            // Print farewell message on signal receipt
            print("\nDecaffeinated. Goodbye! \u{1F344}")
            // Exit cleanly — the assertion is released on process exit
            _Exit(0)
        }

        // Block the main thread indefinitely using the run loop.
        // The process stays alive keeping the power assertion active
        // until the user sends SIGINT (Ctrl+C).
        RunLoop.current.run()
    }
}
