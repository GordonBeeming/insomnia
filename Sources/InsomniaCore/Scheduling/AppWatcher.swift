// AppWatcher.swift — InsomniaCore
//
// Monitors running applications via NSWorkspace notifications to detect
// when a specific app terminates. Used for the "caffeinate while app is
// running" feature — when the watched app quits, caffeination stops.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Monitors NSWorkspace for application lifecycle events.
///
/// Watches for a specific application (by bundle identifier) to terminate,
/// then invokes a callback. This powers the "caffeinate while app is running" mode.
public final class AppWatcher {
    // MARK: - Properties

    /// The bundle identifier of the application being watched.
    /// `nil` when not actively watching any application.
    public private(set) var watchedBundleIdentifier: String?

    /// Callback invoked when the watched application terminates.
    /// Set by the consumer (typically CaffeinationScheduler) before starting a watch.
    public var onWatchedAppTerminated: (() -> Void)?

    /// Observer token for the NSWorkspace notification.
    /// Stored so it can be removed when watching stops.
    private var notificationObserver: NSObjectProtocol?

    // MARK: - Initialization

    /// Creates a new app watcher.
    ///
    /// The watcher starts in an inactive state. Call `watch(bundleIdentifier:)`
    /// to begin monitoring a specific application.
    public init() {
        // No setup needed — watching begins when explicitly requested
    }

    /// Cleans up the notification observer on deallocation.
    deinit {
        // Remove any active notification observer to prevent dangling references
        stopWatching()
    }

    // MARK: - Watching

    /// Begins watching for the termination of the app with the given bundle identifier.
    ///
    /// If already watching an app, the previous watch is stopped first.
    /// When the watched app terminates, `onWatchedAppTerminated` is called.
    ///
    /// - Parameter bundleIdentifier: The bundle identifier of the app to watch (e.g., "com.apple.Safari").
    public func watch(bundleIdentifier: String) {
        // Stop any existing watch before starting a new one
        stopWatching()
        // Store the bundle identifier we're watching
        watchedBundleIdentifier = bundleIdentifier

        #if canImport(AppKit)
        // Subscribe to workspace app termination notifications
        notificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract the terminated app's info from the notification
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let terminatedBundleID = app.bundleIdentifier else {
                return
            }
            // Check if the terminated app matches our watched bundle ID
            if terminatedBundleID == self.watchedBundleIdentifier {
                // The watched app has quit — invoke the callback
                self.onWatchedAppTerminated?()
                // Clean up since the watch is fulfilled
                self.stopWatching()
            }
        }
        #endif
    }

    /// Stops watching for app termination.
    ///
    /// Removes the notification observer and clears the watched bundle identifier.
    /// Safe to call multiple times or when not watching.
    public func stopWatching() {
        #if canImport(AppKit)
        // Remove the notification observer if one is active
        if let observer = notificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            notificationObserver = nil
        }
        #endif
        // Clear the watched bundle identifier
        watchedBundleIdentifier = nil
    }

    // MARK: - Running Applications

    /// Returns a list of currently running applications with their names and bundle identifiers.
    ///
    /// Queries `NSWorkspace` for all running applications and returns them as
    /// simple tuples for display in the UI or CLI.
    ///
    /// - Returns: An array of tuples containing the app name and bundle identifier.
    public static func runningApplications() -> [(name: String, bundleIdentifier: String)] {
        #if canImport(AppKit)
        // Query NSWorkspace for all running apps
        return NSWorkspace.shared.runningApplications.compactMap { app in
            // Only include apps that have both a name and bundle identifier
            guard let name = app.localizedName,
                  let bundleID = app.bundleIdentifier else {
                return nil
            }
            // Return as a named tuple for easy consumption
            return (name: name, bundleIdentifier: bundleID)
        }
        #else
        // AppKit not available — return empty list
        return []
        #endif
    }
}
