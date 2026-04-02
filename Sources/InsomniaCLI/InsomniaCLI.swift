// InsomniaCLI.swift — InsomniaCLI
//
// The root @main entry point for the Insomnia command-line interface.
// Registers all subcommands and sets the default subcommand to StatusCommand,
// so running bare `insomnia` without arguments displays the current status.
// Uses swift-argument-parser for declarative CLI argument parsing.

import ArgumentParser
import InsomniaCore

/// The root command for the Insomnia CLI.
///
/// Provides subcommands for caffeinating, decaffeinating, toggling,
/// timed/app-watching modes, status display, and schedule management.
/// The default subcommand is `status`, so running `insomnia` alone
/// shows the current caffeination state.
@main
struct InsomniaCLI: ParsableCommand {
    /// Command configuration defining the CLI name, help text, version, and subcommands.
    static let configuration = CommandConfiguration(
        // The binary name used in help output and error messages
        commandName: "insomnia",
        // One-line description shown in help — uses Dapple's tagline
        abstract: Dapple.tagline,
        // Extended discussion shown below the abstract — Dapple ASCII art
        discussion: Dapple.asciiArt,
        // Semantic version for --version flag
        version: "1.0.0",
        // All available subcommands registered here
        subcommands: [
            CaffeinateCommand.self,
            DecaffeinateCommand.self,
            ToggleCommand.self,
            CaffeinateForCommand.self,
            CaffeinateUntilCommand.self,
            CaffeinateWhileCommand.self,
            StatusCommand.self,
            ScheduleCommand.self,
        ],
        // Running bare `insomnia` without a subcommand shows status
        defaultSubcommand: StatusCommand.self
    )
}
