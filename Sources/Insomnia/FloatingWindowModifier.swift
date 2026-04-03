// FloatingWindowModifier.swift — Insomnia GUI
//
// A SwiftUI ViewModifier that makes a window float above all other windows.
// Uses NSViewRepresentable to find the specific hosting NSWindow rather than
// iterating all app windows. Important for LSUIElement menu bar apps where
// windows should stay visible even when the user clicks on other applications.

import AppKit
import SwiftUI

/// Makes the hosting NSWindow float above all other windows.
///
/// Finds the NSWindow backing the SwiftUI view and sets its
/// level to `.floating`. This keeps Insomnia's windows visible even when
/// focus moves to another app — important for a menu bar utility.
struct FloatingWindow: ViewModifier {
    /// Applies the floating window level to the view's hosting window.
    func body(content: Content) -> some View {
        content
            .background(FloatingWindowAccessor())
    }
}

/// Resolves the specific NSWindow hosting the modified SwiftUI view.
///
/// Uses `NSViewRepresentable` to access the underlying `NSView`, then
/// reads its `.window` property to set the level. This avoids iterating
/// all app windows and eliminates timing-based delays.
private struct FloatingWindowAccessor: NSViewRepresentable {
    /// Creates the backing NSView and sets its window to floating level.
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Set floating level once the view is attached to a window
        DispatchQueue.main.async {
            view.window?.level = .floating
        }
        return view
    }

    /// Re-applies floating level when the view updates (e.g., window reappears).
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.level = .floating
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
