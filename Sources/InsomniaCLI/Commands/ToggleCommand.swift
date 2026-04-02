// ToggleCommand.swift — InsomniaCLI
//
// Implements the `insomnia toggle` subcommand for toggling between
// caffeinated and decaffeinated states. Requires the GUI application
// to be running since toggle state is managed by the GUI's scheduler.

import ArgumentParser
import Foundation
import InsomniaCore

/// Toggles the caffeination state between active and inactive.
///
/// When caffeinated, toggles to decaffeinated. When decaffeinated,
/// toggles to caffeinated indefinitely. Requires the GUI to be running
/// since the toggle state is owned by the GUI's power assertion manager.
struct ToggleCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "toggle",
        // Description shown in help output
        abstract: "Toggle caffeination state"
    )

    // MARK: - Execution

    /// Runs the toggle command.
    ///
    /// Checks if the GUI is running and sends a toggle command via IPC.
    /// If the GUI is not running, prints an error suggesting alternatives.
    mutating func run() throws {
        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send toggle command via IPC
            let response = try client.send(.toggle)
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — toggle requires persistent state from the app
            CLIOutput.printError("Insomnia.app is not running. Start the app or use `insomnia caffeinate` for standalone mode.")
        }
    }
}
