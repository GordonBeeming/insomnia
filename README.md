# Insomnia

> The tool that never sleeps

```
    .-o-OO-o-.
   (__________)
      |    |
      |    |
      |____|
      Dapple
```

## What is Insomnia?

A macOS caffeinate utility that keeps your Mac awake. Menu bar app + CLI, powered by IOKit power assertions.

## Features

- Caffeinate indefinitely, for a duration, or until a specific time
- Caffeinate while a specific app is running
- Recurring schedules (e.g., weekdays 9am-5pm)
- Menu bar icon with status and remaining time
- Dynamic dock icon (awake/sleep states)
- Full CLI with standalone mode (works without the GUI)
- IPC: CLI controls the GUI app when running

## Installation

### Build from Source

Requires macOS 14+ and Swift 5.9+.

```bash
git clone https://github.com/gordonbeeming/insomnia.git
cd insomnia
swift build -c release
```

The CLI binary will be at `.build/release/insomnia`.

### Manual Install

Download the latest release from [GitHub Releases](https://github.com/gordonbeeming/insomnia/releases):

- **Insomnia.dmg** -- GUI app, drag to Applications
- **insomnia** -- standalone CLI binary

### Homebrew (recommended)

> **Note:** There is an unrelated app called "Insomnia" (API client) in the default Homebrew cask repo.
> Always use the fully qualified name below to install this app.

```bash
brew install --cask gordonbeeming/tap/insomnia
```

## CLI Usage

The CLI connects to the running GUI app via IPC. If the GUI isn't running, commands that support it enter standalone mode.

```bash
# Show current status (default command)
insomnia
insomnia status
insomnia status --json

# Caffeinate indefinitely
insomnia caffeinate
insomnia caffeinate --display    # also prevent display sleep

# Caffeinate for a duration
insomnia for 30m
insomnia for 2h
insomnia for 1h30m
insomnia for 90s

# Caffeinate until a specific time
insomnia until 17:00
insomnia until 23:30

# Caffeinate while an app is running
insomnia while Safari
insomnia while com.apple.Xcode

# Stop caffeination
insomnia decaffeinate

# Toggle caffeination on/off
insomnia toggle

# Manage schedules
insomnia schedule list
insomnia schedule add --weekdays mon,tue,wed,thu,fri --start 09:00 --end 17:00
insomnia schedule remove <uuid>
```

## GUI

The menu bar app provides:

- **Status display** with caffeination state and remaining time
- **Quick toggle** between caffeinated and decaffeinated
- **Timed caffeination** with preset durations (15m, 30m, 1h, 2h) or custom
- **Caffeinate until** a specific time via date picker
- **App watching** -- select a running app to caffeinate while it's open
- **Schedule editor** -- create recurring caffeination windows by weekday and time
- **Settings** -- icon style, launch at login, display sleep prevention, dock icon visibility

## Building

### Prerequisites

- macOS 14+
- Xcode 15+ or Swift 5.9+ toolchain

### Build

```bash
swift build              # debug build
swift build -c release   # optimized release build
swift build --build-tests  # build including tests
```

### Test

```bash
swift test               # run all tests
swift test --parallel    # run tests in parallel
```

### Release

```bash
./Scripts/build-release.sh           # build CLI + .app bundle
./Scripts/package-for-homebrew.sh 1.0.0  # create Homebrew archive
```

## Architecture

The project has three targets defined in `Package.swift`:

- **InsomniaCore** -- shared library with power assertion management, scheduling, IPC protocol, and models. Links IOKit for hardware-level sleep prevention.
- **Insomnia** -- SwiftUI menu bar GUI app. Uses `MenuBarExtra` for the dropdown, `@Observable` view models, and an `AppDelegate` for IPC server lifecycle.
- **InsomniaCLI** -- command-line interface built with swift-argument-parser. Communicates with the GUI via Unix domain socket IPC, or runs standalone with direct IOKit assertions.

IPC uses a length-prefixed JSON protocol over Unix domain sockets at `~/Library/Application Support/Insomnia/insomnia.sock`.

## License

MIT -- see [LICENSE](LICENSE)

## Credits

Kept awake by Dapple the Mushroom -- Gordon's Claude buddy and the official Insomnia mascot. Dapple is a small mushroom who sits beside the prompt and makes sure nobody falls asleep on the job.

Made by [Gordon Beeming](https://gordonbeeming.com)
