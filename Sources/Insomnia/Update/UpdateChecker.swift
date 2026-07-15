// UpdateChecker.swift — Insomnia GUI
//
// Checks for application updates by querying the GitHub Releases API.
// Manages periodic background checks, version comparison, and DMG
// download for user-initiated updates. Uses @Observable for SwiftUI
// integration with the menu bar UI.

import AppKit
import Foundation
import InsomniaCore

/// Manages update checking against GitHub Releases.
///
/// Periodically queries the GitHub API for the latest release, compares
/// the version with the running app, and provides download functionality.
/// All state properties are observable for automatic SwiftUI view updates.
@Observable
final class UpdateChecker {
    // MARK: - Constants

    /// The GitHub Releases API endpoint for the latest release.
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/gordonbeeming/insomnia/releases/latest"
    )!

    /// Minimum interval between checks to avoid API rate limiting (5 minutes).
    private static let minimumCheckInterval: TimeInterval = 300

    /// Interval between automatic background checks (1 hour).
    private static let periodicCheckInterval: TimeInterval = 3600

    // MARK: - Observable State

    /// Whether a newer version is available on GitHub.
    private(set) var isUpdateAvailable: Bool = false

    /// The version string of the latest release (e.g., "0.6").
    private(set) var latestVersion: String?

    /// The direct download URL for the latest DMG.
    private(set) var downloadURL: URL?

    /// Whether an update check is currently in progress.
    private(set) var isChecking: Bool = false

    /// Whether a DMG download is currently in progress.
    private(set) var isDownloading: Bool = false

    /// Error message from the last failed operation, if any.
    private(set) var lastError: String?

    // MARK: - Private State

    /// Timer for periodic background update checks.
    private var timer: Timer?

    /// Timestamp of the last successful or attempted check.
    private var lastCheckDate: Date?

    // MARK: - Periodic Checks

    /// Starts periodic background update checks every hour.
    ///
    /// Also fires an immediate check on startup. In dev builds, periodic
    /// checks are disabled to avoid unnecessary API calls during development.
    func startPeriodicChecks() {
        // Skip periodic checks in dev builds
        guard !BuildEnvironment.isDev else { return }
        // Fire an initial check after a short startup delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            Task { await self.checkForUpdate() }
        }
        // Schedule the repeating timer for hourly checks
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.periodicCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.checkForUpdate()
            }
        }
    }

    /// Stops periodic background update checks.
    func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Update Check

    /// Checks for a newer version by querying the GitHub Releases API.
    ///
    /// Compares the latest release tag with the running app's bundle version.
    /// Updates all observable state properties based on the result.
    /// Skips the check if one was performed within the last 5 minutes.
    ///
    /// - Parameter force: If `true`, ignores the minimum check interval.
    func checkForUpdate(force: Bool = false) async {
        // Rate limit: skip if checked recently (unless forced)
        if !force, let lastCheck = lastCheckDate,
           Date().timeIntervalSince(lastCheck) < Self.minimumCheckInterval {
            return
        }
        // Don't start a new check if one is already running
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        defer { isChecking = false }
        // Record the check time
        lastCheckDate = Date()
        do {
            // Fetch the latest release from GitHub
            let release = try await fetchLatestRelease()
            // Parse the remote version from the tag
            guard let remoteVersion = AppVersion(string: release.tagName) else {
                lastError = "Could not parse release tag: \(release.tagName)"
                return
            }
            // Parse the local version from the app bundle
            let localVersionString = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0"
            guard let localVersion = AppVersion(string: localVersionString) else {
                lastError = "Could not parse local version: \(localVersionString)"
                return
            }
            // Compare versions — update available if remote is newer
            if remoteVersion > localVersion {
                latestVersion = remoteVersion.description
                // Extract the DMG download URL from the release assets
                if let dmg = release.dmgAsset,
                   let url = URL(string: dmg.browserDownloadUrl),
                   Self.isAllowedDownloadHost(url) {
                    downloadURL = url
                    isUpdateAvailable = true
                } else {
                    // Update exists but no valid DMG asset — still notify
                    downloadURL = nil
                    isUpdateAvailable = true
                }
            } else {
                isUpdateAvailable = false
                latestVersion = nil
                downloadURL = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Download Update

    /// Downloads the latest DMG and opens it for the user to install.
    ///
    /// The DMG is saved to `~/Downloads` and automatically mounted
    /// via `NSWorkspace` so the user can drag the app to Applications.
    /// File I/O is performed off the main thread to avoid UI jank.
    func downloadAndOpenInstaller() async {
        guard let url = downloadURL else {
            lastError = "No download URL available"
            return
        }
        guard !isDownloading else { return }
        isDownloading = true
        lastError = nil
        defer { isDownloading = false }
        do {
            // Download the DMG to a temporary location
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            // Capture the version string before moving to background
            let version = latestVersion ?? "latest"
            // Perform file I/O off the main thread
            let destinationURL = try await Task.detached {
                let fileName = "Insomnia-\(version).dmg"
                let downloadsDir = FileManager.default.urls(
                    for: .downloadsDirectory,
                    in: .userDomainMask
                ).first!
                let destination = downloadsDir.appendingPathComponent(fileName)
                // Remove any existing file at the destination
                try? FileManager.default.removeItem(at: destination)
                // Move the downloaded file to ~/Downloads
                try FileManager.default.moveItem(at: tempURL, to: destination)
                return destination
            }.value
            // Open the DMG on the main thread — macOS will mount it
            NSWorkspace.shared.open(destinationURL)
        } catch {
            lastError = "Download failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Helpers

    /// Fetches the latest release from the GitHub Releases API.
    ///
    /// - Returns: The parsed `GitHubRelease` model.
    /// - Throws: If the network request or JSON decoding fails.
    private func fetchLatestRelease() async throws -> GitHubRelease {
        // Build the request with a User-Agent header (required by GitHub API)
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("Insomnia-macOS", forHTTPHeaderField: "User-Agent")
        // Perform the network request
        let (data, response) = try await URLSession.shared.data(for: request)
        // Validate the HTTP status code
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw UpdateError.httpError(statusCode: httpResponse.statusCode)
        }
        // Decode the JSON response using snake_case conversion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Validates that a download URL points to an allowed GitHub host.
    ///
    /// Only allows HTTPS downloads from GitHub's known asset hosts to prevent
    /// downloading from spoofed or malicious URLs in a compromised release.
    ///
    /// - Parameter url: The download URL to validate.
    /// - Returns: `true` if the URL uses HTTPS and points to an allowed host.
    private static func isAllowedDownloadHost(_ url: URL) -> Bool {
        // Only allow HTTPS downloads
        guard url.scheme == "https" else { return false }
        // Allowlisted GitHub asset hosts
        let allowedHosts = [
            "github.com",
            "objects.githubusercontent.com",
        ]
        guard let host = url.host else { return false }
        return allowedHosts.contains(host)
    }
}

// MARK: - Update Errors

/// Errors specific to the update checking process.
enum UpdateError: Error, LocalizedError {
    /// The GitHub API returned a non-200 status code.
    case httpError(statusCode: Int)

    /// Human-readable error description.
    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "GitHub API returned status \(code)"
        }
    }
}
