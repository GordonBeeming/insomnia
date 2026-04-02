// InsomniaConfiguration.swift — InsomniaCore
//
// Persistent configuration for the Insomnia application, backed by UserDefaults.
// Stores user preferences for icon style, menu bar behavior, sleep prevention
// mode, launch-at-login, and schedule rules. Uses @Observable for SwiftUI binding.

import Foundation

// MARK: - Icon Style

/// The visual style of the menu bar icon.
///
/// Controls which icon is displayed in the macOS menu bar
/// when the application is running.
public enum IconStyle: String, Codable, CaseIterable, Sendable {
    /// The default coffee cup icon style.
    case `default` = "default"
    /// A minimal, simplified icon style.
    case minimal = "minimal"
    /// A Dapple mushroom-themed icon style.
    case dapple = "dapple"

    /// Human-readable label for display in settings UI.
    public var displayName: String {
        switch self {
        case .default: return "Default"
        case .minimal: return "Minimal"
        case .dapple: return "Dapple"
        }
    }
}

// MARK: - UserDefaults Keys

/// Keys used for storing configuration values in UserDefaults.
///
/// Uses BuildEnvironment.defaultsPrefix to namespace keys, so dev and prod
/// builds store settings independently and don't interfere with each other.
private enum ConfigKeys {
    /// Whether to hide the menu bar icon when decaffeinated.
    static var hideIconWhenDecaffeinated: String { "\(BuildEnvironment.defaultsPrefix)hideIconWhenDecaffeinated" }
    /// The selected icon style for the menu bar.
    static var iconStyle: String { "\(BuildEnvironment.defaultsPrefix)iconStyle" }
    /// Whether to show remaining time in the menu bar title.
    static var showRemainingTimeInMenuBar: String { "\(BuildEnvironment.defaultsPrefix)showRemainingTimeInMenuBar" }
    /// Whether to prevent display sleep (vs. only system sleep).
    static var preventDisplaySleep: String { "\(BuildEnvironment.defaultsPrefix)preventDisplaySleep" }
    /// Whether to launch the app at system login.
    static var launchAtLogin: String { "\(BuildEnvironment.defaultsPrefix)launchAtLogin" }
    /// JSON-encoded array of schedule rules.
    static var scheduleRules: String { "\(BuildEnvironment.defaultsPrefix)scheduleRules" }
}

// MARK: - Configuration

/// Observable configuration model backed by UserDefaults.
///
/// Reads and writes all preferences to UserDefaults, providing reactive
/// properties for SwiftUI views. Schedule rules are stored as JSON data.
@Observable
public final class InsomniaConfiguration {
    // MARK: - Properties

    /// The UserDefaults instance used for storage.
    private let defaults: UserDefaults

    /// Whether to hide the menu bar icon when the app is decaffeinated.
    /// When `true`, the icon only appears while caffeination is active.
    public var hideIconWhenDecaffeinated: Bool {
        didSet {
            // Persist the updated value to UserDefaults
            defaults.set(hideIconWhenDecaffeinated, forKey: ConfigKeys.hideIconWhenDecaffeinated)
        }
    }

    /// The visual style of the menu bar icon.
    public var iconStyle: IconStyle {
        didSet {
            // Persist the raw value string to UserDefaults
            defaults.set(iconStyle.rawValue, forKey: ConfigKeys.iconStyle)
        }
    }

    /// Whether to show the remaining caffeination time in the menu bar title.
    public var showRemainingTimeInMenuBar: Bool {
        didSet {
            // Persist the updated value to UserDefaults
            defaults.set(showRemainingTimeInMenuBar, forKey: ConfigKeys.showRemainingTimeInMenuBar)
        }
    }

    /// Whether to prevent display sleep in addition to system sleep.
    /// When `true`, uses `preventUserIdleDisplaySleep` instead of system sleep.
    public var preventDisplaySleep: Bool {
        didSet {
            // Persist the updated value to UserDefaults
            defaults.set(preventDisplaySleep, forKey: ConfigKeys.preventDisplaySleep)
        }
    }

    /// Whether the application should launch automatically at system login.
    public var launchAtLogin: Bool {
        didSet {
            // Persist the updated value to UserDefaults
            defaults.set(launchAtLogin, forKey: ConfigKeys.launchAtLogin)
        }
    }

    /// The configured schedule rules for automatic caffeination.
    public var scheduleRules: [ScheduleRule] {
        didSet {
            // Encode the rules as JSON and persist to UserDefaults
            saveScheduleRules()
        }
    }

    // MARK: - Initialization

    /// Creates a configuration instance, loading values from UserDefaults.
    ///
    /// - Parameter defaults: The UserDefaults instance to use. Defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Load each property from UserDefaults with sensible defaults
        self.hideIconWhenDecaffeinated = defaults.bool(forKey: ConfigKeys.hideIconWhenDecaffeinated)
        // Load icon style from raw string, defaulting to .default
        if let styleString = defaults.string(forKey: ConfigKeys.iconStyle),
           let style = IconStyle(rawValue: styleString) {
            self.iconStyle = style
        } else {
            self.iconStyle = .default
        }
        self.showRemainingTimeInMenuBar = defaults.bool(forKey: ConfigKeys.showRemainingTimeInMenuBar)
        self.preventDisplaySleep = defaults.bool(forKey: ConfigKeys.preventDisplaySleep)
        self.launchAtLogin = defaults.bool(forKey: ConfigKeys.launchAtLogin)
        // Load schedule rules from JSON data
        self.scheduleRules = InsomniaConfiguration.loadScheduleRules(from: defaults)
    }

    // MARK: - Schedule Rule Persistence

    /// Loads schedule rules from UserDefaults.
    ///
    /// Decodes the JSON data stored at the schedule rules key. Returns an
    /// empty array if no data exists or if decoding fails.
    ///
    /// - Parameter defaults: The UserDefaults to load from.
    /// - Returns: The decoded array of schedule rules.
    private static func loadScheduleRules(from defaults: UserDefaults) -> [ScheduleRule] {
        // Read the JSON data from UserDefaults
        guard let data = defaults.data(forKey: ConfigKeys.scheduleRules) else {
            // No saved rules — return empty array
            return []
        }
        // Attempt to decode the JSON into ScheduleRule array
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([ScheduleRule].self, from: data)
        } catch {
            // Decoding failed — log and return empty array
            print("Failed to decode schedule rules: \(error)")
            return []
        }
    }

    /// Saves the current schedule rules to UserDefaults as JSON data.
    private func saveScheduleRules() {
        let encoder = JSONEncoder()
        do {
            // Encode the rules as JSON
            let data = try encoder.encode(scheduleRules)
            // Store the JSON data in UserDefaults
            defaults.set(data, forKey: ConfigKeys.scheduleRules)
        } catch {
            // Encoding failed — log the error
            print("Failed to encode schedule rules: \(error)")
        }
    }

    // MARK: - Convenience

    /// The preferred assertion type based on the current configuration.
    ///
    /// Returns display sleep prevention if `preventDisplaySleep` is enabled,
    /// otherwise returns system sleep prevention.
    public var preferredAssertionType: PowerAssertionType {
        // Choose assertion type based on the display sleep setting
        return preventDisplaySleep ? .preventUserIdleDisplaySleep : .preventUserIdleSystemSleep
    }
}
