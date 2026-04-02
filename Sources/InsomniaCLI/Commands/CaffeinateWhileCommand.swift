// CaffeinateWhileCommand.swift — InsomniaCLI
//
// Implements the `insomnia while <app>` subcommand for app-watching
// caffeination. Keeps the system awake while a specified application
// is running. Resolves app names to bundle identifiers automatically.

import ArgumentParser
import Foundation
import InsomniaCore

/// Starts caffeination that lasts while a specific application is running.
///
/// Accepts an app name or bundle identifier. When the watched application
/// terminates, caffeination stops automatically. Supports standalone mode
/// using AppWatcher and PowerAssertionManager directly.
struct CaffeinateWhileCommand: ParsableCommand {
    /// Command configuration for help text and command name.
    static let configuration = CommandConfiguration(
        // The subcommand name used on the command line
        commandName: "while",
        // Description shown in help output
        abstract: "Caffeinate while an application is running"
    )

    // MARK: - Arguments

    /// The application name or bundle identifier to watch.
    ///
    /// Can be a human-readable name (e.g., "Safari", "Xcode") or a
    /// full bundle identifier (e.g., "com.apple.Safari").
    @Argument(help: "Application name or bundle identifier to watch")
    var app: String

    // MARK: - Execution

    /// Runs the caffeinate-while command.
    ///
    /// Resolves the app argument to a bundle identifier, then either
    /// sends the command via IPC or enters standalone mode.
    mutating func run() throws {
        // Resolve the app name/bundle ID to a confirmed bundle identifier
        let resolved = resolveApp(app)

        // Create an IPC client to check GUI status and send commands
        let client = IPCClient()

        if client.isGUIRunning {
            // GUI is running — send caffeinateWhile command via IPC
            let bundleID = resolved?.bundleIdentifier ?? app
            let response = try client.send(.caffeinateWhile(bundleIdentifier: bundleID))
            // Display the formatted response from the GUI
            CLIOutput.printResponse(response)
        } else {
            // GUI not running — enter standalone mode watching the app
            try runStandalone(resolved: resolved)
        }
    }

    // MARK: - App Resolution

    /// Resolves an app name or bundle identifier to a running application.
    ///
    /// Searches the list of currently running applications for a match
    /// by name (case-insensitive) or exact bundle identifier.
    ///
    /// - Parameter query: The app name or bundle identifier to search for.
    /// - Returns: A tuple of (name, bundleIdentifier) if found, or nil.
    private func resolveApp(_ query: String) -> (name: String, bundleIdentifier: String)? {
        // Get the list of all currently running applications
        let running = AppWatcher.runningApplications()
        // Search for a match by name (case-insensitive) or bundle ID
        let match = running.first { entry in
            // Check if the query matches the app name (case-insensitive)
            entry.name.localizedCaseInsensitiveCompare(query) == .orderedSame
            // Or if the query matches the bundle identifier exactly
            || entry.bundleIdentifier == query
        }
        return match
    }

    // MARK: - Standalone Mode

    /// Runs in standalone mode watching the specified application.
    ///
    /// Creates a PowerAssertionManager and AppWatcher, monitors the
    /// target application, and decaffeinates when it terminates.
    ///
    /// - Parameter resolved: The resolved app info, or nil if not found in running apps.
    private func runStandalone(resolved: (name: String, bundleIdentifier: String)?) throws {
        // Validate that we have a resolvable app
        guard let appInfo = resolved else {
            CLIOutput.printError("Application '\(app)' is not currently running.")
            // Show a hint about what apps are available
            let running = AppWatcher.runningApplications()
            if !running.isEmpty {
                print("Running applications:")
                // List up to 10 running apps for discoverability
                for entry in running.prefix(10) {
                    print("  - \(entry.name) (\(entry.bundleIdentifier))")
                }
                if running.count > 10 {
                    print("  ... and \(running.count - 10) more")
                }
            }
            return
        }

        // Create the power assertion manager with real IOKit provider
        let manager = PowerAssertionManager()
        // Start caffeination in app-watching mode
        try manager.caffeinateWhileRunning(
            bundleIdentifier: appInfo.bundleIdentifier,
            appName: appInfo.name
        )

        // Display the standalone mode banner with current state
        CLIOutput.printStandalone(state: manager.state)

        // Create an AppWatcher to monitor the target application
        let watcher = AppWatcher()
        // Set up the termination callback to decaffeinate and exit
        watcher.onWatchedAppTerminated = {
            // The watched app has quit — decaffeinate
            try? manager.decaffeinate()
            print("\n\(appInfo.name) has quit. Decaffeinated. Goodbye! \u{1F344}")
            _Exit(0)
        }
        // Start watching the target application
        watcher.watch(bundleIdentifier: appInfo.bundleIdentifier)

        // Install SIGINT (Ctrl+C) handler for early clean shutdown
        signal(SIGINT) { _ in
            print("\nDecaffeinated. Goodbye! \u{1F344}")
            _Exit(0)
        }

        // Block the main thread indefinitely using the run loop.
        // The AppWatcher callback or SIGINT will terminate the process.
        RunLoop.current.run()
    }
}
