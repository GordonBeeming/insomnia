// PowerAssertionManager.swift — InsomniaCore
//
// Manages IOKit power assertions to prevent macOS from sleeping.
// Uses a protocol-based design so that IOKit calls can be mocked in tests.
// The manager is @Observable for SwiftUI/Observation framework integration.

import Foundation
import IOKit.pwr_mgt

// MARK: - Power Assertion Provider Protocol

/// Protocol abstracting IOKit power assertion operations for testability.
///
/// By injecting a conforming type, unit tests can verify assertion
/// creation and release without requiring actual IOKit system calls.
public protocol PowerAssertionProviding: AnyObject, Sendable {
    /// Creates a power assertion of the given type with the specified reason.
    ///
    /// - Parameters:
    ///   - type: The IOKit assertion type string (e.g., kIOPMAssertionTypePreventUserIdleSystemSleep).
    ///   - reason: A human-readable reason string stored in the assertion properties.
    /// - Returns: An opaque assertion identifier used to release the assertion later.
    /// - Throws: If the assertion could not be created (e.g., permission denied).
    func createAssertion(type: String, reason: String) throws -> UInt32

    /// Releases a previously created power assertion.
    ///
    /// - Parameter assertionID: The identifier returned by `createAssertion`.
    /// - Throws: If the assertion could not be released.
    func releaseAssertion(_ assertionID: UInt32) throws
}

// MARK: - IOKit Power Assertion Provider

/// Default implementation that creates real IOKit power assertions.
///
/// This class wraps `IOPMAssertionCreateWithProperties` and `IOPMAssertionRelease`
/// to provide actual system-level sleep prevention.
public final class IOKitPowerAssertionProvider: PowerAssertionProviding, @unchecked Sendable {
    /// Shared instance for convenience — stateless, so sharing is safe.
    public static let shared = IOKitPowerAssertionProvider()

    /// Creates the provider. No configuration needed since IOKit is stateless.
    public init() {}

    /// Creates an IOKit power assertion using IOPMAssertionCreateWithProperties.
    ///
    /// - Parameters:
    ///   - type: The assertion type string from IOKit constants.
    ///   - reason: Human-readable reason for the assertion.
    /// - Returns: The IOKit assertion ID for later release.
    /// - Throws: `PowerAssertionError.creationFailed` if IOKit returns an error.
    public func createAssertion(type: String, reason: String) throws -> UInt32 {
        // Build the assertion properties dictionary required by IOKit
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionNameKey: reason,
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
        ]
        // Will hold the assertion ID on success
        var assertionID: IOPMAssertionID = 0
        // Create the assertion through IOKit
        let result = IOPMAssertionCreateWithProperties(
            properties as CFDictionary,
            &assertionID
        )
        // Check if IOKit returned success
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(ioReturn: result)
        }
        // Return the assertion ID for tracking and later release
        return assertionID
    }

    /// Releases an IOKit power assertion by its ID.
    ///
    /// - Parameter assertionID: The ID returned when the assertion was created.
    /// - Throws: `PowerAssertionError.releaseFailed` if IOKit returns an error.
    public func releaseAssertion(_ assertionID: UInt32) throws {
        // Release the assertion through IOKit
        let result = IOPMAssertionRelease(assertionID)
        // Check if IOKit returned success
        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.releaseFailed(ioReturn: result)
        }
    }
}

// MARK: - Power Assertion Errors

/// Errors that can occur during power assertion operations.
public enum PowerAssertionError: Error, LocalizedError {
    /// IOKit failed to create the power assertion.
    case creationFailed(ioReturn: Int32)
    /// IOKit failed to release the power assertion.
    case releaseFailed(ioReturn: Int32)
    /// Attempted an operation that requires an active assertion when none exists.
    case noActiveAssertion

    /// Human-readable description for logging and error display.
    public var errorDescription: String? {
        switch self {
        case .creationFailed(let code):
            return "Failed to create power assertion (IOReturn: \(code))"
        case .releaseFailed(let code):
            return "Failed to release power assertion (IOReturn: \(code))"
        case .noActiveAssertion:
            return "No active power assertion to release"
        }
    }
}

// MARK: - Power Assertion Manager

/// Manages the lifecycle of IOKit power assertions.
///
/// This class is the primary interface for creating and releasing power assertions.
/// It tracks the current assertion state and provides convenience methods for
/// timed and indefinite caffeination.
///
/// Uses `@Observable` for integration with SwiftUI and the Observation framework.
@Observable
public final class PowerAssertionManager {
    // MARK: - Properties

    /// The current power/caffeination state.
    /// Observed by the UI to update display and menu bar status.
    public private(set) var state: PowerState = .decaffeinated

    /// The type of assertion currently active, if any.
    public private(set) var currentAssertionType: PowerAssertionType?

    /// The IOKit assertion ID for the currently active assertion.
    /// Used to release the assertion when decaffeinating.
    private var assertionID: UInt32?

    /// Timer used for timed caffeination modes.
    /// Fires when the caffeination period expires.
    private var expiryTimer: Timer?

    /// The provider used to create and release IOKit assertions.
    /// Injected for testability — defaults to real IOKit calls.
    private let provider: PowerAssertionProviding

    // MARK: - Initialization

    /// Creates a power assertion manager with the given provider.
    ///
    /// - Parameter provider: The assertion provider to use. Defaults to the real IOKit provider.
    public init(provider: PowerAssertionProviding = IOKitPowerAssertionProvider.shared) {
        // Store the provider for creating/releasing assertions
        self.provider = provider
    }

    // MARK: - Caffeination Methods

    /// Starts indefinite caffeination with the specified assertion type.
    ///
    /// If already caffeinated, the existing assertion is released first.
    ///
    /// - Parameter type: The type of sleep to prevent. Defaults to preventing display sleep.
    /// - Throws: If the IOKit assertion cannot be created.
    public func caffeinate(type: PowerAssertionType = .preventUserIdleDisplaySleep) throws {
        // Release any existing assertion before creating a new one
        try releaseExistingAssertion()
        // Create the new assertion via the provider
        let id = try provider.createAssertion(
            type: type.iokitAssertionType,
            reason: "Insomnia: \(type.displayDescription)"
        )
        // Store the assertion ID and update state
        assertionID = id
        currentAssertionType = type
        state = .caffeinatedIndefinitely
    }

    /// Starts timed caffeination for a specific duration.
    ///
    /// Creates a power assertion and schedules a timer to automatically
    /// release it after the specified interval.
    ///
    /// - Parameters:
    ///   - duration: The duration in seconds to keep the assertion active.
    ///   - type: The type of sleep to prevent. Defaults to preventing display sleep.
    /// - Throws: If the IOKit assertion cannot be created.
    public func caffeinate(for duration: TimeInterval, type: PowerAssertionType = .preventUserIdleDisplaySleep) throws {
        // Calculate the end date from the duration
        let endDate = Date().addingTimeInterval(duration)
        // Delegate to the until-date method
        try caffeinate(until: endDate, type: type)
    }

    /// Starts timed caffeination until a specific date.
    ///
    /// Creates a power assertion and schedules a timer to automatically
    /// release it when the target date arrives.
    ///
    /// - Parameters:
    ///   - date: The date at which to automatically decaffeinate.
    ///   - type: The type of sleep to prevent. Defaults to preventing display sleep.
    /// - Throws: If the IOKit assertion cannot be created.
    public func caffeinate(until date: Date, type: PowerAssertionType = .preventUserIdleDisplaySleep) throws {
        // Release any existing assertion before creating a new one
        try releaseExistingAssertion()
        // Create the new assertion via the provider
        let id = try provider.createAssertion(
            type: type.iokitAssertionType,
            reason: "Insomnia: \(type.displayDescription) until \(date)"
        )
        // Store the assertion ID and update state
        assertionID = id
        currentAssertionType = type
        state = .caffeinatedUntil(date)
        // Schedule a timer to auto-decaffeinate when the time expires
        scheduleExpiryTimer(for: date)
    }

    /// Toggles between caffeinated and decaffeinated states.
    ///
    /// If currently decaffeinated, starts indefinite caffeination.
    /// If currently caffeinated (any mode), decaffeinates.
    ///
    /// - Parameter type: The assertion type to use when toggling on. Defaults to display sleep.
    /// - Throws: If creating or releasing the assertion fails.
    public func toggle(type: PowerAssertionType = .preventUserIdleDisplaySleep) throws {
        if state.isActive {
            // Currently active — turn off
            try decaffeinate()
        } else {
            // Currently inactive — turn on indefinitely
            try caffeinate(type: type)
        }
    }

    /// Stops all caffeination and releases the active power assertion.
    ///
    /// Safe to call even if already decaffeinated (no-op in that case).
    ///
    /// - Throws: If the IOKit assertion cannot be released.
    public func decaffeinate() throws {
        // Release the IOKit assertion if one is active
        try releaseExistingAssertion()
        // Reset state to decaffeinated
        state = .decaffeinated
        currentAssertionType = nil
    }

    /// Updates the state to reflect app-watching mode.
    ///
    /// This is called by the CaffeinationScheduler when entering app-watch mode.
    /// The actual assertion creation is handled separately.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The bundle ID of the watched application.
    ///   - appName: The display name of the watched application.
    ///   - type: The assertion type. Defaults to preventing display sleep.
    /// - Throws: If the IOKit assertion cannot be created.
    public func caffeinateWhileRunning(
        bundleIdentifier: String,
        appName: String,
        type: PowerAssertionType = .preventUserIdleDisplaySleep
    ) throws {
        // Release any existing assertion before creating a new one
        try releaseExistingAssertion()
        // Create the new assertion via the provider
        let id = try provider.createAssertion(
            type: type.iokitAssertionType,
            reason: "Insomnia: keeping awake while \(appName) runs"
        )
        // Store the assertion ID and update state
        assertionID = id
        currentAssertionType = type
        state = .caffeinatedWhileRunning(
            bundleIdentifier: bundleIdentifier,
            appName: appName
        )
    }

    // MARK: - Private Helpers

    /// Releases the currently active IOKit assertion, if any.
    ///
    /// Also cancels any active expiry timer. This is a no-op if no assertion is active.
    /// - Throws: If IOKit fails to release the assertion.
    private func releaseExistingAssertion() throws {
        // Cancel any pending expiry timer
        expiryTimer?.invalidate()
        expiryTimer = nil
        // Release the IOKit assertion if we have one
        if let id = assertionID {
            try provider.releaseAssertion(id)
            assertionID = nil
        }
    }

    /// Schedules a timer to automatically decaffeinate at the given date.
    ///
    /// When the timer fires, the assertion is released and state returns to decaffeinated.
    ///
    /// - Parameter date: The date at which the timer should fire.
    private func scheduleExpiryTimer(for date: Date) {
        // Calculate how long until the target date
        let interval = date.timeIntervalSinceNow
        // Don't schedule if the date is already in the past
        guard interval > 0 else {
            // Date already passed — decaffeinate immediately
            try? decaffeinate()
            return
        }
        // Create and schedule the expiry timer on the current run loop
        expiryTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: false
        ) { [weak self] _ in
            // Timer fired — decaffeinate automatically
            try? self?.decaffeinate()
        }
    }
}
