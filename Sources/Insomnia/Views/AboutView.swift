// AboutView.swift — Insomnia GUI
//
// Simple about dialog displaying the Dapple mascot ASCII art, app name,
// tagline, description, version number, and credits. Shown in its own
// window via the "About Insomnia" menu item.

import SwiftUI
import InsomniaCore

/// The about window content, showing mascot art and application information.
///
/// Displays Dapple's ASCII art in a monospaced font, the app name and
/// tagline, a brief description, the version number, and a credits line.
struct AboutView: View {
    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Show the app icon loaded from Resources/AppIcon.icns
            if let icon = AboutView.loadIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .cornerRadius(24)
            }

            // Dapple ASCII art — always shown as the mascot signature
            Text(Dapple.asciiArt)
                .font(.custom("Menlo", size: 14))
                .multilineTextAlignment(.center)

            // Application name in large title font — shows "Dev" suffix in debug builds
            Text(BuildEnvironment.appName)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Mascot tagline
            Text(Dapple.tagline)
                .font(.headline)
                .foregroundStyle(.secondary)

            // About description from the Dapple mascot module
            Text(Dapple.aboutDescription)
                .font(.body)

            // Version number pulled from the bundle
            Text("Version \(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Credits line
            Text("Made with \u{1F344} by Gordon Beeming")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 360)
    }

    // MARK: - Helpers

    /// The app's short version string from the main bundle.
    ///
    /// Falls back to "1.0.0" if the bundle key is missing.
    private var appVersion: String {
        // Read CFBundleShortVersionString from the app bundle
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// Loads the app icon from the application icon image or Resources directory.
    static func loadIcon() -> NSImage? {
        // Use the current application icon if the app is running
        if let app = NSApp {
            return app.applicationIconImage
        }
        // Try from current working directory as fallback
        let cwdPath = FileManager.default.currentDirectoryPath + "/Resources/AppIcon.icns"
        return NSImage(contentsOfFile: cwdPath)
    }
}
