// AppDelegate.swift — Insomnia GUI
//
// NSApplicationDelegate managing the application lifecycle. Owns the shared
// CaffeinationScheduler and IPCServer. Starts the IPC server on launch
// and cleans up all resources on termination.

import AppKit
import InsomniaCore

/// Application delegate that manages the Insomnia app lifecycle.
///
/// Responsibilities:
/// - Creates and owns the shared ``CaffeinationScheduler`` used by both
///   the GUI and the IPC server
/// - Starts the ``IPCServer`` on launch so the CLI can communicate
/// - Releases all power assertions and stops the IPC server on termination
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Shared State

    /// The caffeination scheduler shared across the entire application.
    /// Created once on delegate init and referenced by InsomniaApp via the adaptor.
    let scheduler = CaffeinationScheduler()

    /// The user configuration shared across the application.
    let configuration = InsomniaConfiguration()

    // MARK: - Owned Controllers

    /// The IPC server that receives commands from the CLI.
    /// Initialized lazily when the app finishes launching.
    private var ipcServer: IPCServer?

    // MARK: - NSApplicationDelegate

    /// Called when the application finishes launching.
    ///
    /// Starts the IPC server so the CLI can send commands to this GUI instance.
    /// The server binds to the default Unix domain socket path.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create and start the IPC server backed by our scheduler
        let server = IPCServer(scheduler: scheduler)
        do {
            try server.start()
            ipcServer = server
        } catch {
            // Log the error — the app still works without IPC
            print("Failed to start IPC server: \(error.localizedDescription)")
        }

        // Set the app icon from Resources/AppIcon.icns if available
        // This replaces the generic "exec" terminal icon when running via `swift run`
        loadAppIcon()

        // Ensure the app runs as a menu bar-only app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
    }

    /// Called when the application is about to terminate.
    ///
    /// Releases all active power assertions and stops the IPC server
    /// to ensure clean shutdown and socket cleanup.
    func applicationWillTerminate(_ notification: Notification) {
        // Release all power assertions and stop watches
        do {
            try scheduler.cancelAll()
        } catch {
            print("Failed to cancel caffeination on quit: \(error.localizedDescription)")
        }

        // Stop the IPC server and remove the socket file
        ipcServer?.stop()
        ipcServer = nil
    }

    // MARK: - Private Helpers

    /// Loads AppIcon.icns and sets it as the application icon.
    private func loadAppIcon() {
        // Try loading from the app bundle first (release builds)
        if let bundleIcon = Bundle.main.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = bundleIcon
            return
        }
        // Try from current working directory (most reliable for `swift run`)
        let cwdPath = FileManager.default.currentDirectoryPath + "/Resources/AppIcon.icns"
        if let icon = NSImage(contentsOfFile: cwdPath) {
            NSApp.applicationIconImage = icon
            return
        }
        // Fall back to searching upward from the executable's real path
        let execPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var searchDir = execPath.deletingLastPathComponent()
        for _ in 0..<6 {
            let iconPath = searchDir.appendingPathComponent("Resources/AppIcon.icns").path
            if let icon = NSImage(contentsOfFile: iconPath) {
                NSApp.applicationIconImage = icon
                return
            }
            searchDir = searchDir.deletingLastPathComponent()
        }
    }
}
