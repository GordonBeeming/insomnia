// GitHubRelease.swift — Insomnia GUI
//
// Codable model for the GitHub Releases API response. Only decodes the
// fields needed for update checking: the release tag, page URL, and
// downloadable asset information.

import Foundation

/// Represents a GitHub release from the Releases API.
///
/// Used to decode the response from
/// `https://api.github.com/repos/gordonbeeming/insomnia/releases/latest`.
/// Only the fields needed for update checking are included.
struct GitHubRelease: Codable {
    /// The git tag for this release (e.g., "v0.6").
    let tagName: String

    /// The URL of the release page on GitHub.
    let htmlUrl: String

    /// The downloadable assets attached to this release.
    let assets: [Asset]

    /// A single downloadable file attached to a GitHub release.
    struct Asset: Codable {
        /// The filename of the asset (e.g., "Insomnia-0.6.dmg").
        let name: String

        /// The direct download URL for the asset.
        let browserDownloadUrl: String
    }

    /// Finds the DMG asset for the macOS GUI application.
    ///
    /// Searches the assets list for a file ending in `.dmg`.
    /// - Returns: The DMG asset if found, or `nil` if no DMG is attached.
    var dmgAsset: Asset? {
        // Look for the DMG file in the release assets
        return assets.first { $0.name.hasSuffix(".dmg") }
    }
}
