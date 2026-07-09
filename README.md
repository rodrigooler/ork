<div align="center">

# ⬢ ork

**A native macOS deck for orchestrating AI coding agents.**

Claude Code, Codex, OpenCode, Gemini CLI: every agent in its own terminal,
every terminal in its own git worktree, all in one window.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](#quick-start)
[![License: MIT](https://img.shields.io/badge/License-MIT-00E5FF)](LICENSE)
[![Status](https://img.shields.io/badge/status-pre--alpha-FF2EC8)](#roadmap)

</div>

## Why

Terminal agents multiplied, and running four of them across ad hoc terminal tabs, each one fighting the others for the same working tree, is chaos. ork gives each agent its own terminal and its own git worktree, organized per project, in a single native window. Pure Swift and SwiftUI, no Electron.

## Features

|  | Feature | Status |
|--|---------|--------|
| 🗂 | **Workspaces**: register project folders, each with its own agent fleet | ✅ v0 |
| 🤖 | **Agent sessions**: spawn Claude Code, Codex, OpenCode, Gemini CLI or a plain shell in one click | ✅ v0 |
| 🌿 | **Worktree isolation**: each session runs on its own branch in a dedicated worktree, created with plain `git worktree add` | ✅ v0 |
| ▦ | **Terminal grid**: all sessions side by side | ✅ v0 |
| ⬡ | **Flow view**: workspace and agents as a connected topology, click a node to focus its terminal | ✅ v0 |
| 🛢 | **Data pane per project**: register the Postgres and Redis each project talks to, live reachability probe | ✅ v0 |
| 📊 | **Usage**: token usage from your Claude Code transcripts, 14 day chart | ✅ v0 |
| 🔔 | **Menu bar companion**: running agents, today's tokens and exit notifications from the macOS menu bar | ✅ v0 |
| 🏝 | **Notch glance**: hover the MacBook notch for a quick panel; an animated rail on the notch shows agents at work | ✅ v0 |
| 🎯 | **Focus mode**: isolate one terminal over a dimmed backdrop for high-stakes work, live PTY intact | ✅ v0 |
| 🔎 | Postgres and Redis query consoles | 🗺 roadmap |
| 📈 | Observability pane: Loki, Tempo, Grafana, OpenTelemetry | 🗺 roadmap |
| 📨 | RabbitMQ and Kafka endpoints | 🗺 roadmap |

## Quick start

Requirements: macOS 14+, Xcode 15+ (any recent Swift toolchain).

```sh
git clone git@github.com:rodrigooler/ork.git
cd ork
swift run
```

Or open `Package.swift` in Xcode and hit Run.

Sessions run inside a zsh login shell, so any agent CLI on your shell profile `PATH` (`claude`, `codex`, `opencode`, ...) resolves without configuration.

## Built-in agents

| Agent | Command | Accent |
|-------|---------|--------|
| Claude Code | `claude` | coral |
| Codex | `codex` | green |
| OpenCode | `opencode` | cyan |
| Gemini CLI | `gemini` | blue |
| Shell | `zsh` | amber |

Adding an agent is a one line change in `Sources/Ork/Models.swift` for now. Config file driven agents are on the roadmap.

## How worktree isolation works

When you spawn a session with the worktree switch on, ork runs:

```sh
git -C <workspace> worktree add -b ork/<agent>-<id> <parent>/.ork-worktrees/<repo>/<agent>-<id>
```

The agent starts inside that fresh worktree, on its own branch, so two agents never fight over the same files. Closing a session keeps the worktree on disk (no work is ever lost); prune with `git worktree prune` when you are done.

## Architecture

```
Sources/Ork/
├── OrkApp.swift            entry point, window chrome
├── Theme.swift             design tokens, backdrop, panel styles
├── Models.swift            AgentProfile, Workspace, TerminalSession, DBConnection
├── AppStore.swift          app state + JSON persistence (Application Support)
├── WorktreeService.swift   git worktree plumbing
├── TerminalRegistry.swift  PTY lifecycle, focus tracking, terminal font stack
├── UsageService.swift      token usage from Claude Code transcripts
├── Notifier.swift          exit notifications (osascript)
├── Reachability.swift      TCP probe for data endpoints
├── Logo.swift              menu bar mark (vector source in Assets/logo.svg)
└── Views/                  SwiftUI: sidebar, grid, flow topology, data pane, usage, menu bar panel
```

One external dependency: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation.

Design decisions and trade-offs live in [docs/DESIGN.md](docs/DESIGN.md).

## Roadmap

- [ ] Query console for Postgres (PostgresNIO) and Redis (RediStack)
- [ ] Observability pane: Loki queries, Tempo traces, Grafana links, OTel status
- [ ] RabbitMQ and Kafka endpoints
- [ ] Draggable flow canvas with live agent status parsing
- [ ] Custom agents from a config file
- [ ] Session persistence across launches
- [ ] Proper `.app` bundle, icon, signed releases
- [ ] Worktree janitor: list, merge and prune from the UI

## Inspiration

[paperclip.ing](https://paperclip.ing), [The Maestri](https://www.themaestri.app), [AgentPeek](https://agentpeek.app) and the whole wave of agent-native tooling.

## License

[MIT](LICENSE)
