# Roadmap

Priorities for ork, in order. Items move up or down based on real usage; open an issue if something here matters to you.

## Next (0.6)

- **Custom team roles**: editable per-member role prompts from the team pane. Coordinator and member roles shipped in 0.5.0.
- **Console history**: recall past queries per connection.

## Shipped since 0.5.0

- Team message box: talk to the agent team from the team pane as 'user'.
- Rename agents: give a terminal a human name from the context menu; teams address it by that name.
- Stack layout: tab strip on top, one terminal expanded, the rest collapsed but alive.
- Single main window: a duplicate window stole the terminal views (dead scroll, blank cards).
- Near-zero idle work: git stat polling pauses while the window is hidden and skips frozen or hibernated sessions; pane refresh loops pause when occluded.

## Later

- **Observability pane**: Loki queries, Tempo traces, Grafana links and OpenTelemetry status per project.
- **Queue endpoints**: RabbitMQ and Kafka reachability and basic inspection in the data pane.
- **Draggable flow canvas**: free node placement plus live agent status parsed from the terminal stream.
- **Proper `.app` bundle**: signed and notarized releases, real app icon, native notifications instead of osascript.
- **Notch on external displays**: the glance panel only attaches to the built-in screen today.
- **Scrollable terminal grid**: keep cells usable past six concurrent sessions.

## Shipped in 0.5.0

- Settings window: theme (dark and light), terminal font, behavior toggles.
- Agent-friendly terminal input: Shift+Enter newline, Ctrl+Backspace, image paste and drag-and-drop.
- Git pane: GitKraken-style commit graph, worktree strip, diff panel.
- Session cards show uncommitted diff stats and commits ahead of base.
- Manual sleep and hibernate from the terminal context menu; hibernate frees the CLI's memory and resumes on demand.
- Config file driven agents (agents.json).
- Worktree janitor: diff, merge and prune from the git pane.
- Query consoles for Postgres (PostgresNIO) and Redis (RediStack).
- Agent teams: terminal-to-terminal messaging routed by Ork, shared board.md, message log and team pane.
- Economical team protocol: fixed message shapes, char cap with bounce, per-recipient batching, coordinator role and succession.

## Shipped in 0.4.0

- Workspaces with organization grouping.
- Agent sessions for Claude Code, Codex, OpenCode, Gemini CLI and plain shells.
- Worktree isolation per session.
- Session persistence across relaunches, resuming the agent conversation where the CLI supports it.
- Idle freeze: sessions idling for ten minutes are suspended with SIGSTOP and wake on interaction.
- Focus mode, flow view, usage dashboard, menu bar companion, notch glance panel.
- Data pane with Postgres and Redis reachability probes.
