// AppVersion.swift — InsomniaCore
//
// Parses and compares application version strings. Handles both GitHub
// release tag formats ("v0.6") and bundle version formats ("0.5.42")
// by extracting only the major and minor components for comparison.

import Foundation

/// Represents an application version with major and minor components.
///
/// Supports parsing from multiple formats:
/// - GitHub release tags: `"v0.6"`, `"v1.2"`
/// - Bundle versions: `"0.5.42"`, `"1.0.0"`
/// - Simple versions: `"0.6"`, `"1.2"`
///
/// The build number (third component) is intentionally ignored since
/// release tags only use major.minor versioning.
public struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    /// The major version component (e.g., 0 in "0.6").
    public let major: Int

    /// The minor version component (e.g., 6 in "0.6").
    public let minor: Int

    // MARK: - Initialization

    /// Creates an AppVersion from major and minor components.
    ///
    /// - Parameters:
    ///   - major: The major version number.
    ///   - minor: The minor version number.
    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// Parses a version string into an AppVersion.
    ///
    /// Strips a leading "v" prefix if present, then extracts the first
    /// two dot-separated numeric components. Any third component (build
    /// number) is ignored.
    ///
    /// - Parameter string: The version string to parse (e.g., "v0.6", "0.5.42").
    /// - Returns: An `AppVersion` if parsing succeeds, or `nil` for invalid input.
    public init?(string: String) {
        // Strip the "v" prefix used in GitHub release tags
        var cleaned = string
        if cleaned.hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }
        // Split on dots and take the first two numeric components
        let parts = cleaned.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        self.major = major
        self.minor = minor
    }

    // MARK: - Comparable

    /// Compares two versions by major first, then minor.
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        return lhs.minor < rhs.minor
    }

    // MARK: - CustomStringConvertible

    /// A display-friendly version string (e.g., "0.6").
    public var description: String {
        return "\(major).\(minor)"
    }
}
