// CLIOutput.swift — InsomniaCLI
//
// Formatting utilities for CLI terminal output. Provides ANSI color-coded
// printing for status, responses, errors, and Dapple mascot art.
// Automatically detects whether stdout is a TTY and disables colors
// when output is piped to another process or file.

import Foundation
import InsomniaCore

/// Provides static formatting methods for CLI terminal output.
///
/// All output methods check `isatty(STDOUT_FILENO)` before applying
/// ANSI escape codes, ensuring clean output when piped or redirected.
enum CLIOutput {
    // MARK: - ANSI Color Codes

    /// ANSI escape code to reset all text formatting.
    private static let reset = "\u{001B}[0m"
    /// ANSI escape code for bold text.
    private static let bold = "\u{001B}[1m"
    /// ANSI escape code for green text (used for active/success states).
    private static let green = "\u{001B}[32m"
    /// ANSI escape code for red text (used for errors and inactive states).
    private static let red = "\u{001B}[31m"
    /// ANSI escape code for yellow text (used for warnings).
    private static let yellow = "\u{001B}[33m"
    /// ANSI escape code for cyan text (used for informational highlights).
    private static let cyan = "\u{001B}[36m"

    // MARK: - Color Detection

    /// Whether the terminal supports ANSI color codes.
    ///
    /// Returns `true` if stdout is connected to a TTY (interactive terminal).
    /// Returns `false` if output is being piped or redirected to a file,
    /// preventing garbled escape sequences in non-terminal contexts.
    private static var supportsColor: Bool {
        // isatty returns non-zero if the file descriptor is a terminal
        return isatty(STDOUT_FILENO) != 0
    }

    /// Wraps text in ANSI color codes if the terminal supports them.
    ///
    /// - Parameters:
    ///   - text: The text to colorize.
    ///   - color: The ANSI color escape code to apply.
    /// - Returns: The colorized string, or plain text if colors are unsupported.
    private static func colorize(_ text: String, _ color: String) -> String {
        // Only apply ANSI codes when outputting to a real terminal
        guard supportsColor else { return text }
        return "\(color)\(text)\(reset)"
    }

    /// Wraps text in bold ANSI formatting if the terminal supports it.
    ///
    /// - Parameter text: The text to make bold.
    /// - Returns: The bold string, or plain text if colors are unsupported.
    private static func boldText(_ text: String) -> String {
        // Only apply bold when outputting to a real terminal
        guard supportsColor else { return text }
        return "\(bold)\(text)\(reset)"
    }

    // MARK: - Status Output

    /// Prints a formatted status display for the given power state.
    ///
    /// Shows the current caffeination state with color coding:
    /// green for active states, red for decaffeinated.
    /// Includes remaining time information for timed modes.
    ///
    /// - Parameter state: The current power state to display.
    static func printStatus(_ state: PowerState) {
        // Print a bold header line
        print(boldText("Insomnia Status"))
        print(String(repeating: "─", count: 30))

        if state.isActive {
            // Active state — show in green with details
            print("  State: \(colorize(state.displayDescription, green))")
            // Show remaining time for timed caffeination
            if let remaining = state.remainingDescription {
                print("  Remaining: \(colorize(remaining, cyan))")
            }
        } else {
            // Inactive state — show in red
            print("  State: \(colorize("Decaffeinated", red))")
        }
        // Blank line after status block for readability
        print()
    }

    /// Prints a formatted IPC response from the GUI application.
    ///
    /// Handles all response types: success messages, status reports,
    /// schedule lists, and error messages with appropriate coloring.
    ///
    /// - Parameter response: The IPC response to format and display.
    static func printResponse(_ response: IPCResponse) {
        switch response {
        case .success(let message):
            // Success messages in green
            print(colorize("✓ \(message)", green))

        case .status(let state, let schedules):
            // Full status display with state and schedule count
            printStatus(state)
            if !schedules.isEmpty {
                // Show schedule count when schedules exist
                print(boldText("Schedules: \(schedules.count)"))
                // List each schedule rule with its summary
                for rule in schedules {
                    let status = rule.isEnabled ? colorize("●", green) : colorize("○", red)
                    print("  \(status) \(rule.displaySummary)")
                }
                print()
            }

        case .scheduleList(let schedules):
            // Display all schedule rules
            if schedules.isEmpty {
                print(colorize("No schedules configured.", yellow))
            } else {
                print(boldText("Schedules"))
                print(String(repeating: "─", count: 30))
                // List each rule with enabled/disabled indicator
                for rule in schedules {
                    let status = rule.isEnabled ? colorize("●", green) : colorize("○", red)
                    print("  \(status) [\(rule.id.uuidString.prefix(8))] \(rule.displaySummary)")
                }
            }
            print()

        case .error(let message):
            // Error messages in red
            printError(message)
        }
    }

    // MARK: - Error Output

    /// Prints a red error message to stdout.
    ///
    /// Prefixes the message with a cross mark for visual distinction.
    ///
    /// - Parameter message: The error message to display.
    static func printError(_ message: String) {
        // Print with red cross prefix for visual error indication
        print(colorize("✗ \(message)", red))
    }

    // MARK: - Standalone Mode Output

    /// Prints the standalone mode banner when running without the GUI.
    ///
    /// Shows Dapple's ASCII art and the current caffeination state,
    /// indicating that the CLI is operating independently.
    ///
    /// - Parameter state: The current power state to display alongside the banner.
    static func printStandalone(state: PowerState) {
        // Show Dapple ASCII art as a visual banner
        print(Dapple.asciiArt)
        print()
        // Standalone mode indicator
        print(boldText("Insomnia standalone mode"))
        print(colorize("(Insomnia.app not running)", yellow))
        print()
        // Show the current state
        printStatus(state)
        // Instruction for how to stop
        print(colorize("Press Ctrl+C to decaffeinate and exit.", cyan))
    }

    /// Prints Dapple's ASCII art with a sleeping indicator.
    ///
    /// Used when the status command runs and the GUI is not active,
    /// showing Dapple in a "sleeping" state.
    static func printDappleSleeping() {
        // Show the Dapple ASCII art
        print(Dapple.asciiArt)
        print()
        // Sleeping indicator — Dapple is not keeping anything awake
        print(colorize("  💤 Dapple is sleeping...", yellow))
        print()
    }
}
