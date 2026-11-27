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
swift build                                        # debug build
swift build -Xswiftc -strict-concurrency=complete  # build with strict concurrency (matches CI)
swift test                                         # 133+ tests
swift run Insomnia                                 # run GUI locally
swift run InsomniaCLI status                       # run CLI
```

**Important**: CI runs Swift 5.10 with strict concurrency checking. Always run `swift build -Xswiftc -strict-concurrency=complete` before pushing to catch actor-isolation errors that don't surface in default debug builds.

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

## Updating a dev's machine to a new release

Restarting Insomnia drops its power assertion. If it was caffeinated and the dev has been idle past the sleep timer, the Mac sleeps the moment the old app quits, and whatever they left running stops. Every upgrade or restart therefore goes like this:

1. **Record the state.** Run `insomnia status --json` and keep `state`, `isActive`, `remainingSeconds` and `schedulesCount`. It must say `"guiRunning": true`; if it doesn't, the snapshot means nothing, so stop and ask.
2. **Upgrade.** `brew upgrade --cask gordonbeeming/tap/insomnia`. Always use the full cask name, because an unrelated `insomnia` cask exists.
3. **Bridge the gap, if `isActive` was true.** Quit the old app (`osascript -e 'tell application id "com.gordonbeeming.insomnia" to quit'`) and wait for its process to exit. Then start `insomnia caffeinate &` right away. With no app running, the CLI runs standalone and holds its own assertion until it's killed. The enforcer never touches it, because it only ends `/usr/bin/caffeinate`.
4. **Start the new app.** `open -a /Applications/Insomnia.app`, then poll `insomnia status --json` until `guiRunning` is true. A restore sent before then runs standalone, where `status` can't see it.
5. **Restore through the app:**
   - Indefinite: `insomnia caffeinate`.
   - Timed: `insomnia for <remainingSeconds, rounded up to a whole minute>`. Don't use `until`: it drops seconds and moves a time that has already passed to tomorrow. If the session had already expired, don't restore anything.
   - While an app runs: `insomnia while <bundle id>`, and only if that app is still running. Otherwise leave Insomnia decaffeinated.
   - If `schedulesCount` was above 0, the active state may have come from a schedule. Check that the schedules survived the restart instead of replaying the state by hand.
6. **End the bridge.** Kill the standalone `insomnia caffeinate` from step 3. Then run `insomnia status` again and confirm it matches step 1 before saying the install is done.

Never run `/Applications/Insomnia.app/Contents/MacOS/insomnia`. The filesystem is case-insensitive, so that path is the GUI binary: it starts a second app that takes over the IPC socket. Use `insomnia` from the PATH, which is the CLI.

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
