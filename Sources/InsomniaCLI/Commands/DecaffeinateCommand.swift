// DecaffeinateCommand.swift — InsomniaCLI
//
// Implements the `insomnia decaffeinate` subcommand for stopping all
// active caffeination. Requires the GUI application to be running
// since there is no persistent standalone state to decaffeinate.

import ArgumentParser
import Foundation
import InsomniaCore

/// Stops all active caffeination, allowing the system to sleep normally.
///
/// This command only works when the GUI application is running, because
/// the GUI owns the persistent power assertion state. If the GUI is not
/// running, prints an informational error message.
struct DecaffeinateCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "decaffeinate",
        // Description shown in help output
        abstract: "Stop all caffeination"
    )

    // MARK: - Execution

    /// Runs the decaffeinate command.
    ///
    /// Checks if the GUI is running and sends a decaffeinate command via IPC.
    /// If the GUI is not running, prints an error explaining there is nothing
    /// to decaffeinate.
    mutating func run() throws {
        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send decaffeinate command via IPC
            let response = try client.send(.decaffeinate)
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — nothing to decaffeinate
            CLIOutput.printError("Insomnia.app is not running. Nothing to decaffeinate.")
        }
    }
}
