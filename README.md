<div align="center">

<img src="Assets/logo.png" width="150" alt="ork">

**A native macOS deck for orchestrating AI coding agents.**

Claude Code, Codex, OpenCode, Gemini CLI, Grok: every agent in its own
terminal, every terminal in its own git worktree, all in one window.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14+-000000?logo=apple&logoColor=white)](#install)
[![License: MIT](https://img.shields.io/badge/License-MIT-00E5FF)](LICENSE)
[![Release](https://img.shields.io/github/v/release/rodrigooler/ork?color=F96B2F)](https://github.com/rodrigooler/ork/releases)

</div>

## Why

Terminal agents multiplied, and running four of them across ad hoc terminal tabs, each one fighting the others for the same working tree, is chaos. ork gives each agent its own terminal and its own git worktree, organized per project, in a single native window. Pure Swift and SwiftUI, no Electron.

## Features

- **Workspaces and organizations**: register project folders and group them by company or context; each workspace runs its own agent fleet. Drag to reorder projects and organizations in the sidebar.
- **Agent sessions**: spawn Claude Code, Codex, OpenCode, Gemini CLI, Grok or a plain shell in one click; add your own agents via `agents.json`.
- **Agent teams**: join terminals into a team; Ork routes terminal-to-terminal messages, a shared `board.md` holds common context, and a team pane shows members, board and message log. Message shapes, a char cap and per-recipient batching keep the token spend low. The coordinator reviews each delivery in the owner's worktree before accepting it, free members pull the next task from a shared backlog, agents park themselves when done, and finished demands archive to a history folder. A standing `protocol.md` lets agents recover the messaging recipe after context compaction, and a Rebrief button pushes protocol updates to a live team.
- **Worktree isolation**: each session runs on its own branch in a dedicated worktree, created with plain `git worktree add`.
- **Git pane**: commit graph, worktree strip and diff viewer; merge a worktree into its base branch or prune it without leaving the app. Session cards show uncommitted diff stats and commits ahead.
- **Terminal grid, stack and focus mode**: all sessions side by side, or a tab strip with one terminal expanded and the rest collapsed but alive; isolate one terminal over a dimmed backdrop, live PTY intact.
- **Flow view**: workspace and agents as a connected topology; click a node to focus its terminal.
- **Session persistence**: open sessions survive a relaunch, reattach to the same worktree and resume the agent conversation where the CLI supports it.
- **Idle freeze, sleep and hibernate**: a session idling for ten minutes is suspended with SIGSTOP and stops burning CPU; any interaction wakes it. Right-click a terminal to sleep it manually, or hibernate it to free the CLI's memory and resume the conversation later.
- **Data pane per project**: register the Postgres and Redis each project talks to, with a live reachability probe and built-in query consoles.
- **Usage dashboard**: token usage from your Claude Code transcripts, 14 day chart.
- **Menu bar companion and notch glance**: running agents, today's tokens and exit notifications in the menu bar; hover the MacBook notch for a quick panel.
- **Agent-friendly input**: Shift+Enter inserts a newline, Ctrl+Backspace deletes a word, Cmd+Backspace kills the line; paste (Ctrl+V) or drop an image and its path is typed into the prompt, ready for the agent to read. Scrollback stays where you put it while agents stream; Shift+wheel and Shift+drag reach ork's scrollback and selection even when the CLI captures the mouse, and Cmd+click opens links.
- **Privacy mode**: one toggle narrows the sidebar, menu bar and notch to the current project's organization, so a screen recording for one client never shows the others.
- **Settings** (Cmd+,): dark or light theme, terminal font and size, worktree default, idle freeze, notifications, custom agents.

## Install

Requires macOS 14 or newer on Apple Silicon.

One-liner, installs `Ork.app` into /Applications:

```sh
curl -fsSL https://raw.githubusercontent.com/rodrigooler/ork/main/install.sh | sh
```

Or grab the latest zip from [Releases](https://github.com/rodrigooler/ork/releases), unpack it and drag `Ork.app` into Applications. Releases are ad-hoc signed, not notarized, so browser downloads need the quarantine flag cleared once:

```sh
xattr -dr com.apple.quarantine /Applications/Ork.app
```

ork checks GitHub for a newer release on launch; when one is out, an update button shows up in the sidebar footer and swaps the app in place.

### Build from source

Requirements: macOS 14+, Xcode 15+ (any recent Swift toolchain).

```sh
git clone https://github.com/rodrigooler/ork.git
cd ork
swift run -c release
```

Or open `Package.swift` in Xcode and hit Run.

Always run with `-c release`. Terminal emulation parses every byte the agents print; a debug build skips optimization and makes busy TUIs feel sluggish.

Sessions run inside an interactive zsh login shell, so any agent CLI on your shell `PATH` (`claude`, `codex`, `opencode`, ...) resolves exactly as in your terminal, including exports from `~/.zshrc`.

## Built-in agents

| Agent | Command | Accent |
|-------|---------|--------|
| Claude Code | `claude` | coral |
| Codex | `codex` | green |
| OpenCode | `opencode` | cyan |
| Gemini CLI | `gemini` | blue |
| Grok CLI | `grok` | silver |
| Shell | `zsh` | amber |

Custom agents live in `~/Library/Application Support/Ork/agents.json`, one entry per agent with `slug`, `name` and `command`, plus optional `symbol` (SF Symbol), `tint` (`#RRGGBB`) and `resumeCommand`. Edit and reload from Settings.

## How worktree isolation works

When you spawn a session with the worktree switch on, ork runs:

```sh
git -C <workspace> worktree add -b ork/<agent>-<id> <parent>/.ork-worktrees/<repo>/<agent>-<id>
```

The agent starts inside that fresh worktree, on its own branch, so two agents never fight over the same files. Closing a session keeps the worktree on disk (no work is ever lost); merge it into the base branch or prune it from the git pane when you are done.

## Architecture

```
Sources/Ork/
├── OrkApp.swift            entry point, window chrome, font registration
├── Theme.swift             design tokens, motion voice, backdrop, panel styles
├── Models.swift            AgentProfile, Workspace, TerminalSession, DBConnection
├── AppStore.swift          app state + JSON persistence (Application Support)
├── AgentConfig.swift       custom agents from agents.json
├── WorktreeService.swift   git worktree plumbing
├── TerminalRegistry.swift  PTY lifecycle, focus tracking, terminal font stack
├── FreezeService.swift     SIGSTOP/SIGCONT for idle sessions
├── TeamService.swift       team messaging: outbox watcher, routing, board
├── GitService.swift        git plumbing for the git pane (log, diff, merge)
├── GitGraph.swift          commit graph lane assignment
├── QueryService.swift      Postgres and Redis query consoles
├── NotchPanel.swift        notch glance panel (borderless NSPanel)
├── UsageService.swift      token usage from Claude Code transcripts
├── Notifier.swift          exit notifications (osascript)
├── Reachability.swift      TCP probe for data endpoints
├── Logo.swift              brand mark, Dock icon, bundled Orbitron face
└── Views/                  SwiftUI: sidebar, grid, flow topology, git pane, team pane, data pane, usage, menu bar panel
```

External dependencies: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation, [PostgresNIO](https://github.com/vapor/postgres-nio) and [RediStack](https://github.com/swift-server/RediStack) for the query consoles.

Design decisions and trade-offs live in [docs/DESIGN.md](docs/DESIGN.md).

## Roadmap

The plan lives in [ROADMAP.md](ROADMAP.md). Next up: agent tool timeline, custom team roles, and console history.

## Inspiration

[paperclip.ing](https://paperclip.ing), [The Maestri](https://www.themaestri.app), [AgentPeek](https://agentpeek.app) and the whole wave of agent-native tooling.

## License

[MIT](LICENSE)
