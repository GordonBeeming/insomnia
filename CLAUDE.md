# Insomnia

A macOS caffeinate utility — menu bar app + CLI. Mascot: Dapple the Mushroom.

## Tech Stack

- Swift (SwiftUI + AppKit hybrid)
- macOS 14+, Apple Silicon (arm64) only
- IOKit power assertions (native, no shelling out to `caffeinate`)
- Swift ArgumentParser for CLI
- XCTest for unit + integration tests

## Project Structure

Three targets in `Package.swift`:
- `InsomniaCore` — shared library (power management, scheduling, IPC, models)
- `Insomnia` — macOS GUI app (MenuBarExtra + AppKit)
- `InsomniaCLI` — CLI tool

## Build & Test

```bash
swift build          # debug build
swift test           # 118+ tests
swift run Insomnia   # run GUI locally
swift run InsomniaCLI status  # run CLI
```

## Code Comments

85%+ comment coverage required. Every file needs:
- File header explaining purpose
- `///` doc comments on public APIs
- Inline comments explaining intent on significant code blocks

## Versioning

- Tags: `v{major}.{minor}` (e.g., `v0.2`, `v0.3`) — no patch number
- Build number: GitHub Actions run number becomes the patch
- Bundle version: `{major}.{minor}.{runNumber}` (e.g., `0.2.42`)
- The `.0` patch in tags is meaningless — never use `v0.2.0`

## Distribution

- Homebrew: `brew install --cask gordonbeeming/tap/insomnia`
  - Always use fully qualified name (upstream "Insomnia" API client conflicts)
  - Cask auto-updated by CI on release via deploy key
- GitHub Releases: signed + notarized DMG + CLI binary
- No App Store (IOKit needs unsandboxed access)

## CI/CD

- `.github/workflows/build.yml`
- Push/PR: build + test only
- Release (published): build + test + sign + notarize + DMG + upload + update Homebrew tap
- Secrets: `DEVELOPER_ID_CERTIFICATE`, `DEVELOPER_ID_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, `HOMEBREW_TAP_DEPLOY_KEY`

## Dev vs Prod

Debug builds use separate identifiers (`BuildEnvironment.swift`):
- App name: "Insomnia Dev"
- IPC socket: `~/Library/Application Support/Insomnia Dev/insomnia.sock`
- UserDefaults prefix: `com.insomnia.dev.*`
- "(Dev)" suffix in status text

This lets dev and prod run side-by-side.

## Key Files

- `Sources/InsomniaCore/Power/PowerAssertionManager.swift` — IOKit assertion lifecycle
- `Sources/InsomniaCore/IPC/IPCServer.swift` — Unix domain socket server
- `Sources/InsomniaCore/Models/BuildEnvironment.swift` — dev/prod separation
- `Sources/Insomnia/InsomniaApp.swift` — @main, MenuBarExtra scene
- `Sources/Insomnia/Views/MenuBarView.swift` — main dropdown menu
- `Sources/Insomnia/AppDelegate.swift` — lifecycle, IPC server, icon loading
- `Scripts/build-release.sh` — builds CLI + .app bundle (args: version, build number)
- `Resources/AppIcon.icns` — Dapple mushroom icon

## Window Focus Pattern

LSUIElement apps need special handling to show windows:
1. `openWindow(id:)` to open
2. `NSApp.activate(ignoringOtherApps: true)` after short delay
The app always stays in `.accessory` mode (no dock icon).
