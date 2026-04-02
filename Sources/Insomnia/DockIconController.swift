// DockIconController.swift — Insomnia GUI
//
// Manages the dock tile icon by generating simple programmatic placeholder
// images based on the current PowerState. Real artwork will replace these
// placeholders in a future release — for now, colored circles provide
// clear visual feedback (green = awake, gray = sleep).

import AppKit
import InsomniaCore

/// Controls the application's dock tile icon based on caffeination state.
///
/// Generates simple colored circle icons programmatically and applies them
/// to the dock tile via `NSApp.applicationIconImage`. Call ``update(for:)``
/// whenever the power state changes.
final class DockIconController {
    // MARK: - Constants

    /// The size of the generated dock icon images in points.
    private static let iconSize: CGFloat = 128

    // MARK: - Public API

    /// Updates the dock tile icon to reflect the given power state.
    ///
    /// Generates a colored circle image:
    /// - Green for any active caffeination state
    /// - Gray for the decaffeinated (idle) state
    ///
    /// - Parameter state: The current power state to represent visually.
    func update(for state: PowerState) {
        // Generate the appropriate icon based on activity state
        let icon = state.isActive ? makeAwakeIcon() : makeSleepIcon()
        // Apply the icon to the running application
        NSApp.applicationIconImage = icon
        // Force the dock tile to redraw immediately
        NSApp.dockTile.display()
    }

    // MARK: - Private Icon Generators

    /// Creates a green circle icon representing the awake/caffeinated state.
    ///
    /// - Returns: An `NSImage` with a green filled circle.
    private func makeAwakeIcon() -> NSImage {
        // Green circle signals active caffeination
        return makeCircleIcon(color: .systemGreen)
    }

    /// Creates a gray circle icon representing the sleep/decaffeinated state.
    ///
    /// - Returns: An `NSImage` with a gray filled circle.
    private func makeSleepIcon() -> NSImage {
        // Gray circle signals inactive/idle state
        return makeCircleIcon(color: .systemGray)
    }

    /// Generates a simple filled circle icon of the given color.
    ///
    /// The circle is drawn centered within a square canvas of
    /// ``iconSize`` x ``iconSize`` points.
    ///
    /// - Parameter color: The fill color for the circle.
    /// - Returns: An `NSImage` containing the colored circle.
    private func makeCircleIcon(color: NSColor) -> NSImage {
        let size = NSSize(width: Self.iconSize, height: Self.iconSize)
        // Create the image and draw into its graphics context
        let image = NSImage(size: size)
        image.lockFocus()
        // Fill the circle within the full bounds
        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8))
        color.setFill()
        path.fill()
        image.unlockFocus()
        return image
    }
}
