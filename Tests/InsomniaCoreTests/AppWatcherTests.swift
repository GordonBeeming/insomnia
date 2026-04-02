// AppWatcherTests.swift — InsomniaCoreTests
//
// Lightweight tests for AppWatcher covering initialization, watching state,
// stop behavior, and the static runningApplications method.
// Note: Full notification-based testing requires a running NSApplication
// loop, so these tests focus on state management.

import XCTest
@testable import InsomniaCore

/// Tests for the AppWatcher class.
final class AppWatcherTests: XCTestCase {

    // MARK: - Initialization

    /// Verifies that a new AppWatcher starts in an inactive state.
    func testInitialState() {
        // Create a fresh watcher
        let watcher = AppWatcher()
        // Should not be watching anything initially
        XCTAssertNil(watcher.watchedBundleIdentifier)
        XCTAssertNil(watcher.onWatchedAppTerminated)
    }

    // MARK: - Watch State

    /// Tests that calling watch sets the watched bundle identifier.
    func testWatchSetsBundleIdentifier() {
        let watcher = AppWatcher()
        // Start watching an app
        watcher.watch(bundleIdentifier: "com.apple.Safari")
        // The bundle identifier should be stored
        XCTAssertEqual(watcher.watchedBundleIdentifier, "com.apple.Safari")
    }

    /// Tests that calling watch replaces the previous watch.
    func testWatchReplacesExisting() {
        let watcher = AppWatcher()
        // Watch Safari first
        watcher.watch(bundleIdentifier: "com.apple.Safari")
        // Then watch Xcode — should replace
        watcher.watch(bundleIdentifier: "com.apple.dt.Xcode")
        // Should now be watching Xcode
        XCTAssertEqual(watcher.watchedBundleIdentifier, "com.apple.dt.Xcode")
    }

    // MARK: - Stop Watching

    /// Tests that stopWatching clears the watched bundle identifier.
    func testStopWatching() {
        let watcher = AppWatcher()
        // Start watching
        watcher.watch(bundleIdentifier: "com.apple.Safari")
        XCTAssertNotNil(watcher.watchedBundleIdentifier)
        // Stop watching
        watcher.stopWatching()
        // Should be cleared
        XCTAssertNil(watcher.watchedBundleIdentifier)
    }

    /// Tests that stopWatching is safe to call when not watching.
    func testStopWatchingWhenNotWatching() {
        let watcher = AppWatcher()
        // Should not crash when called without an active watch
        watcher.stopWatching()
        XCTAssertNil(watcher.watchedBundleIdentifier)
    }

    // MARK: - Running Applications

    /// Tests that runningApplications returns a non-empty list.
    /// This test may vary by environment but should always find some running apps.
    func testRunningApplicationsReturnsApps() {
        // Query running applications
        let apps = AppWatcher.runningApplications()
        // At minimum, the test runner itself should be running
        XCTAssertFalse(apps.isEmpty, "Should find at least one running application")
    }

    /// Tests that running application entries have non-empty names and bundle IDs.
    func testRunningApplicationsHaveValidEntries() {
        // Query running applications
        let apps = AppWatcher.runningApplications()
        // Each entry should have a non-empty name and bundle identifier
        for app in apps {
            XCTAssertFalse(app.name.isEmpty, "App name should not be empty")
            XCTAssertFalse(app.bundleIdentifier.isEmpty, "Bundle ID should not be empty")
        }
    }

    // MARK: - Callback

    /// Tests that the callback property can be set.
    func testCallbackCanBeSet() {
        let watcher = AppWatcher()
        var callbackCalled = false
        // Set a callback
        watcher.onWatchedAppTerminated = {
            callbackCalled = true
        }
        // Manually invoke to verify it was set correctly
        watcher.onWatchedAppTerminated?()
        XCTAssertTrue(callbackCalled)
    }
}
