// FloatingWindowModifier.swift — Insomnia GUI
//
// A SwiftUI ViewModifier that makes a window float above all other windows.
// Used for LSUIElement menu bar apps where windows should stay visible
// even when the user clicks on other applications.

import SwiftUI

/// Makes the hosting NSWindow float above all other windows.
///
/// Finds the NSWindow backing the SwiftUI view on appear and sets its
/// level to `.floating`. This keeps Insomnia's windows visible even when
/// focus moves to another app — important for a menu bar utility.
struct FloatingWindow: ViewModifier {
    /// Applies the floating window level to the view's hosting window.
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Find the NSWindow hosting this SwiftUI view and float it
                setFloatingLevel()
            }
    }

    /// Searches the app's windows for the one hosting this view and sets it to float.
    private func setFloatingLevel() {
        // Slight delay to ensure the window is created and visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Set all non-main windows to floating level
            // (MenuBarExtra doesn't create a standard NSWindow)
            for window in NSApp.windows where window.isVisible {
                window.level = .floating
            }
        }
    }
}

/// Convenience extension for applying the floating window modifier.
extension View {
    /// Makes the hosting window float above all other windows.
    func floatingWindow() -> some View {
        modifier(FloatingWindow())
    }
}
