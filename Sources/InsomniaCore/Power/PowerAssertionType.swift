// PowerAssertionType.swift — InsomniaCore
//
// Defines the types of power assertions that can be created via IOKit.
// Each case maps to a specific IOKit power assertion constant that controls
// whether the system or display is allowed to idle-sleep.

import IOKit.pwr_mgt

/// Represents the type of IOKit power assertion to create.
///
/// Power assertions prevent macOS from entering various sleep states.
/// The two supported types control system sleep and display sleep independently.
public enum PowerAssertionType: String, Codable, CaseIterable, Sendable {
    /// Prevents the system from sleeping due to user inactivity.
    /// The display may still turn off, but the CPU and disk remain active.
    case preventUserIdleSystemSleep

    /// Prevents the display from sleeping due to user inactivity.
    /// This implicitly also prevents system sleep since the display is active.
    case preventUserIdleDisplaySleep

    /// The IOKit assertion type string used when creating power assertions.
    ///
    /// Maps each case to the corresponding `kIOPMAssertion*` constant
    /// that IOKit expects in `IOPMAssertionCreateWithProperties`.
    public var iokitAssertionType: String {
        switch self {
        case .preventUserIdleSystemSleep:
            // Corresponds to kIOPMAssertionTypePreventUserIdleSystemSleep
            return kIOPMAssertionTypePreventUserIdleSystemSleep as String
        case .preventUserIdleDisplaySleep:
            // Corresponds to kIOPMAssertionTypePreventUserIdleDisplaySleep
            return kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }
    }

    /// A human-readable description of what this assertion type does.
    public var displayDescription: String {
        switch self {
        case .preventUserIdleSystemSleep:
            // Describes system-level sleep prevention
            return "Prevent system sleep"
        case .preventUserIdleDisplaySleep:
            // Describes display-level sleep prevention
            return "Prevent display sleep"
        }
    }
}
