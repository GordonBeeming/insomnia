// Dapple.swift — InsomniaCore
//
// Dapple is the Insomnia mascot — a friendly mushroom that never sleeps.
// This enum provides ASCII art, tagline, and about text for use in the
// CLI output, GUI about window, and help screens.

import Foundation

/// The Insomnia mascot: Dapple the Mushroom.
///
/// Provides static assets related to the mascot, including ASCII art
/// for terminal display, a tagline for branding, and an about description
/// for the application's about window.
public enum Dapple {
    /// ASCII art representation of Dapple for terminal and help output.
    ///
    /// Designed to be compact and recognizable at monospace font sizes.
    public static let asciiArt = """
      .-o-OO-o-.
     (__________)
      | @  @ |
      |      |
      |------|
       Dapple
    """

    /// The application's tagline, suitable for headers and splash screens.
    public static let tagline = "Insomnia — the tool that never sleeps"

    /// A brief description of the mascot for the about window.
    public static let aboutDescription = "Kept awake by Dapple the Mushroom 🍄"
}
