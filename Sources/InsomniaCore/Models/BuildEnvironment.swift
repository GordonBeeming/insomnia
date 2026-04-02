// BuildEnvironment.swift — InsomniaCore
//
// Provides build-variant-aware constants so dev (debug) and prod (release)
// builds can run side-by-side without conflicting on IPC sockets,
// UserDefaults keys, or bundle identifiers.

import Foundation

/// Build environment constants that differ between debug and release builds.
///
/// Debug builds use "Insomnia Dev" naming and separate storage paths so they
/// can run alongside a production Homebrew install without conflicts.
public enum BuildEnvironment {
    // MARK: - Build Variant Detection

    /// Whether this is a debug (development) build.
    public static var isDev: Bool {
        #if DEBUG
        // Debug builds are dev builds — separate from production
        return true
        #else
        // Release builds are production
        return false
        #endif
    }

    // MARK: - App Identity

    /// The display name shown in menus, windows, and the dock.
    public static var appName: String {
        // Dev builds get a "Dev" suffix so you can tell them apart in the menu bar
        isDev ? "Insomnia Dev" : "Insomnia"
    }

    /// The bundle identifier for this build variant.
    public static var bundleIdentifier: String {
        // Separate bundle IDs prevent settings/state from colliding
        isDev ? "com.gordonbeeming.insomnia.dev" : "com.gordonbeeming.insomnia"
    }

    // MARK: - Storage

    /// The Application Support subdirectory name for this build variant.
    public static var appSupportDirectoryName: String {
        // Dev gets its own directory to isolate socket and data files
        isDev ? "Insomnia Dev" : "Insomnia"
    }

    /// The UserDefaults key prefix for this build variant.
    public static var defaultsPrefix: String {
        // Separate prefixes prevent dev and prod settings from interfering
        isDev ? "com.insomnia.dev." : "com.insomnia."
    }

    // MARK: - IPC

    /// The directory containing the IPC socket file.
    public static var socketDirectory: String {
        // Use Application Support with the variant-specific subdirectory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.path
        return "\(appSupport)/\(appSupportDirectoryName)"
    }

    /// The full path to the IPC Unix domain socket.
    public static var socketPath: String {
        // Socket file lives inside the variant-specific app support directory
        return "\(socketDirectory)/insomnia.sock"
    }

    // MARK: - Display

    /// A short label for the menu bar — "(Dev)" suffix in debug builds.
    public static var menuBarSuffix: String {
        // Shows in parentheses after status text so you know which build you're using
        isDev ? " (Dev)" : ""
    }
}
