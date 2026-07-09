# ork design notes

Date: 2026-07-08. Status: v0 scaffold shipped.

## Problem

Running several terminal AI agents (Claude Code, Codex, OpenCode) on one project means juggling terminal tabs and, worse, agents mutating the same working tree at once. Existing orchestrators are mostly web based or closed source.

## Goals (v0)

1. Native macOS app, pure Swift/SwiftUI, open source.
2. Workspaces: one entry per project folder.
3. Sessions: one terminal per agent, spawned in one click.
4. Native git worktree isolation per session.
5. Two layouts: terminal grid and flow topology.
6. Data tooling seed: Postgres/Redis endpoints with a reachability probe.
7. Striking dark visual identity.

## Non-goals (v0)

- DB query execution (needs PostgresNIO/RediStack, roadmap)
- Observability integrations (Loki/Tempo/Grafana/OTel, roadmap)
- Agent output parsing and status detection
- Session persistence across app launches
- Windows/Linux

## Decisions

| Decision | Choice | Alternatives considered |
|---|---|---|
| Project format | SPM executable (`swift run`, or open `Package.swift` in Xcode) | XcodeGen (extra tool for contributors), checked-in xcodeproj (merge pain). SPM builds with the stock toolchain and runs in CI with `swift build`. Cost: no `.app` bundle yet. |
| Terminal emulation | SwiftTerm (MIT), the de facto Swift terminal emulator | Writing a VT100 emulator (months of work), NSTask plus fake scrollback (breaks TUIs like Claude Code). Only dependency in the project. |
| Agent launch | `zsh -l -c "cd <dir> && <command>"` inside a PTY | Direct exec of the agent binary loses the user PATH and shell config. A login shell picks up `~/.zprofile`, so agent CLIs resolve without setup. |
| Worktree placement | `<parent>/.ork-worktrees/<repo>/<agent>-<id>`, branch `ork/<agent>-<id>` | Inside the repo (pollutes status, needs gitignore), Application Support (too far from the code for the user to find). |
| State | JSON in `~/Library/Application Support/Ork/state.json` | SwiftData/CoreData: overkill for two small arrays. |
| Concurrency model | Plain ObservableObject, main-thread mutations, Swift 5 language mode | Strict Swift 6 concurrency fights SwiftTerm's delegate model; not worth it for v0. |
| Terminal lifetime | `TerminalRegistry` keeps the NSViews outside SwiftUI | Letting SwiftUI own them kills the PTY every time the layout switches between grid and flow. |

## Architecture

`AppStore` (ObservableObject) owns workspaces, sessions, connections and selection; views are renderers over it. `TerminalRegistry` maps a session id to a live `LocalProcessTerminalView` so terminals survive re-layout; SwiftUI only reparents the NSView. `WorktreeService` shells out to git. `Reachability` opens a raw TCP connection with a 3 second timeout.

## Known ceilings (deliberate, marked `ponytail:` in code)

- `git worktree add` blocks the calling thread (subsecond on local repos).
- Closing a session drops the PTY and lets SIGHUP kill the child instead of a tracked SIGTERM.
- The grid does not scroll; 6+ sessions get small cells.
- The reachability probe proves TCP connect, not protocol auth.

## Next

See the README roadmap. First candidates: query consoles and config file agents.
