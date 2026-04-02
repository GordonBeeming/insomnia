// StatusCommand.swift — InsomniaCLI
//
// Implements the `insomnia status` subcommand (also the default command).
// Displays the current caffeination state. Supports --json flag for
// machine-readable output. Shows Dapple sleeping when GUI is not running.

import ArgumentParser
import Foundation
import InsomniaCore

/// Displays the current caffeination status.
///
/// This is the default subcommand — running bare `insomnia` without
/// arguments shows the status. When the GUI is running, queries it
/// via IPC. When the GUI is not running, shows Dapple sleeping.
struct StatusCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "status",
        // Description shown in help output
        abstract: "Show current caffeination status (default command)"
    )

    // MARK: - Options

    /// When set, outputs status as JSON for machine-readable consumption.
    ///
    /// The JSON output includes: state, isActive, remainingSeconds, and
    /// schedulesCount for easy parsing by scripts and automation tools.
    @Flag(name: .long, help: "Output status as JSON")
    var json: Bool = false

    // MARK: - Execution

    /// Runs the status command.
    ///
    /// Queries the GUI via IPC if running, or shows a standalone status
    /// message with Dapple sleeping ASCII art if the GUI is not active.
    mutating func run() throws {
        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — query status via IPC
            let response = try client.send(.status)

            if json {
                // JSON output mode — format as machine-readable JSON
                printJSONResponse(response)
            } else {
                // Human-readable output mode
                CLIOutput.printResponse(response)
            }
        } else {
            // GUI not running — show sleeping status
            if json {
                // JSON output for not-running state
                printJSONNotRunning()
            } else {
                // Show Dapple sleeping with informational message
                CLIOutput.printDappleSleeping()
                print("Insomnia.app is not running.")
                print("Use `insomnia caffeinate` for standalone mode.")
            }
        }
    }

    // MARK: - JSON Output

    /// Prints the IPC status response as formatted JSON.
    ///
    /// Extracts the state, active flag, remaining seconds, and schedule
    /// count from the response and outputs as a JSON object.
    ///
    /// - Parameter response: The IPC response to format as JSON.
    private func printJSONResponse(_ response: IPCResponse) {
        switch response {
        case .status(let state, let schedules):
            // Calculate remaining seconds for timed modes
            let remaining: Double? = state.endDate?.timeIntervalSinceNow
            // Build the JSON dictionary
            var jsonDict: [String: Any] = [
                "state": state.displayDescription,
                "isActive": state.isActive,
                "schedulesCount": schedules.count,
                "guiRunning": true,
            ]
            // Only include remaining seconds for timed states
            if let remaining = remaining {
                jsonDict["remainingSeconds"] = max(0, Int(remaining))
            }
            // Serialize and print the JSON
            printJSON(jsonDict)

        default:
            // Non-status responses — wrap in a simple JSON object
            printJSON(["response": "\(response)"])
        }
    }

    /// Prints a JSON object for the not-running state.
    ///
    /// Outputs a minimal JSON object indicating the GUI is not running
    /// and the system is in a decaffeinated state.
    private func printJSONNotRunning() {
        // Minimal JSON indicating inactive state
        let jsonDict: [String: Any] = [
            "state": "Decaffeinated",
            "isActive": false,
            "schedulesCount": 0,
            "guiRunning": false,
        ]
        printJSON(jsonDict)
    }

    /// Serializes a dictionary as pretty-printed JSON and prints to stdout.
    ///
    /// Uses `JSONSerialization` for flexible dictionary-to-JSON conversion.
    /// Falls back to a simple string representation if serialization fails.
    ///
    /// - Parameter dict: The dictionary to serialize as JSON.
    private func printJSON(_ dict: [String: Any]) {
        // Attempt to serialize the dictionary as pretty-printed JSON
        if let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            // Convert to string and print
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }
    }
}
