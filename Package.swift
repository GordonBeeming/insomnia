// swift-tools-version: 5.9
// Package.swift — Insomnia: a macOS caffeination utility
//
// Defines the library, CLI, GUI, and test targets for the Insomnia project.
// The InsomniaCore library contains all shared logic for power assertion
// management, scheduling, IPC, and configuration.

import PackageDescription

/// The Insomnia package provides three executable/library targets:
/// - InsomniaCore: shared library with power management, scheduling, and IPC
/// - InsomniaCLI: command-line interface using swift-argument-parser
/// - Insomnia: GUI application (SwiftUI-based menu bar app)
let package = Package(
    // Package name used for module resolution
    name: "Insomnia",
    // Require macOS 14+ for @Observable macro support
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The shared library consumed by both CLI and GUI targets
        .library(
            name: "InsomniaCore",
            targets: ["InsomniaCore"]
        ),
        // Command-line executable for terminal-based caffeination control
        .executable(
            name: "InsomniaCLI",
            targets: ["InsomniaCLI"]
        ),
        // GUI executable for menu bar-based caffeination control
        .executable(
            name: "Insomnia",
            targets: ["Insomnia"]
        ),
    ],
    dependencies: [
        // swift-argument-parser provides declarative CLI argument parsing
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.5.0"
        ),
    ],
    targets: [
        // MARK: - Library

        // Core library containing power management, scheduling, IPC, and models.
        // Links IOKit framework for hardware-level power assertion control.
        .target(
            name: "InsomniaCore",
            dependencies: [],
            path: "Sources/InsomniaCore",
            linkerSettings: [
                // IOKit is required for IOPMAssertionCreateWithProperties
                .linkedFramework("IOKit")
            ]
        ),

        // MARK: - Executables

        // CLI target depends on InsomniaCore for logic and ArgumentParser for parsing
        .executableTarget(
            name: "InsomniaCLI",
            dependencies: [
                "InsomniaCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/InsomniaCLI"
        ),

        // GUI target depends on InsomniaCore for shared logic
        // Excludes Info.plist and entitlements (used by Xcode, not SPM)
        .executableTarget(
            name: "Insomnia",
            dependencies: ["InsomniaCore"],
            path: "Sources/Insomnia",
            exclude: ["Info.plist", "Insomnia.entitlements"]
        ),

        // MARK: - Tests

        // Unit tests for InsomniaCore components
        .testTarget(
            name: "InsomniaCoreTests",
            dependencies: ["InsomniaCore"],
            path: "Tests/InsomniaCoreTests"
        ),

        // Integration tests that may require system-level access
        .testTarget(
            name: "InsomniaIntegrationTests",
            dependencies: ["InsomniaCore"],
            path: "Tests/InsomniaIntegrationTests"
        ),
    ]
)
