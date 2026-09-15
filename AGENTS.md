# Repository Guidelines

## Project Structure & Module Organization

ClaudeSwitch is a macOS 14+ menu bar app using SwiftUI and AppKit, without an Xcode project, Swift package, or external runtime dependencies.

- `Sources/`: app entry point (`ClaudeSwitchApp.swift`), shared state (`AppState.swift`), views (`MenuView.swift`, `ManagerView.swift`), and styling (`Theme.swift`). Services handle discovery, keychain access, usage requests, notifications, sessions, and terminal launching.
- `Resources/`: bundled icons and artwork; `docs/`: README imagery.
- `Info.plist`: bundle metadata and minimum macOS version.
- `tools/mascot.py`: artwork generator requiring Python and Pillow.
- `build/`: generated app bundle and previews; ignored by Git. No test directory currently exists.

## Build, Test, and Development Commands

Run from the repository root with Swift available through Xcode or Command Line Tools:

- `./build.sh`: clears `build/`, compiles `Sources/*.swift` with optimization, copies resources, and ad-hoc signs `build/ClaudeSwitch.app`.
- `open build/ClaudeSwitch.app`: launches the local build; look in the menu bar, since no Dock icon or window appears initially.
- `./build.sh --install`: builds, stops the running app, and replaces `~/Applications/ClaudeSwitch.app`.
- `python3 tools/mascot.py`: regenerates artwork and previews when changing assets.

## Coding Style & Naming Conventions

Use four-space indentation, same-line opening braces, `UpperCamelCase` type names, and `lowerCamelCase` members. Name Swift files after their primary type or responsibility. Follow nearby code for SwiftUI modifier layout, `///` documentation, and `// MARK: -` sections. Keep UI state on `@MainActor` and usage caching isolated in `UsageClient`'s actor. Reuse `Theme` for visual styling. No formatter or linter is configured.

## Testing Guidelines

No automated test framework, test naming convention, or coverage threshold is configured. For code changes, run `./build.sh` and manually verify affected flows: account discovery, usage refresh, terminal launching, session resume, and notifications. Check both default and custom profiles when changing discovery or launching. Record verification steps and results in the PR.

## Commit & Pull Request Guidelines

History favors short, imperative subjects such as “Add limit alerts and session resume”; `Fix:` appears occasionally. Keep commits focused. PRs should describe the problem, resulting behavior, and validation; link relevant issues and include screenshots for UI changes.

## Security & Configuration

Keep access tokens out of logs, caches, and commits. Store app preferences and usage cache under `~/Library/Application Support/ClaudeSwitch/`. Launching must set `CLAUDE_CONFIG_DIR` only for the new terminal and unset it for the default profile. Preserve deletion confirmations and protection against removing the default profile. Use fictional account details in examples and screenshots.
