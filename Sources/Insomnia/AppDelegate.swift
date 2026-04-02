// AppDelegate.swift — Insomnia GUI
//
// NSApplicationDelegate managing the application lifecycle. Owns the shared
// CaffeinationScheduler, IPCServer, and DockIconController. Starts the IPC
// server on launch and cleans up all resources on termination.

import AppKit
import InsomniaCore

/// Application delegate that manages the Insomnia app lifecycle.
///
/// Responsibilities:
/// - Creates and owns the shared ``CaffeinationScheduler`` used by both
///   the GUI and the IPC server
/// - Starts the ``IPCServer`` on launch so the CLI can communicate
/// - Owns the ``DockIconController`` for dock tile updates
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

    /// The dock icon controller for updating the dock tile image.
    let dockIconController = DockIconController()

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

        // Set initial dock icon to replace the generic "exec" terminal icon
        // This is especially important when running via `swift run` without an app bundle
        dockIconController.update(for: scheduler.powerManager.state)

        // Set the app's menu bar to accessory mode (no dock icon by default)
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
}
