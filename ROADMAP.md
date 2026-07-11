# Roadmap

Priorities for ork, in order. Items move up or down based on real usage; open an issue if something here matters to you.

## Next (0.8)

- **Agent tool timeline**: live tool events per session by tailing the agent's transcript, AgentPeek style, in the notch and session cards.
- **Custom team roles**: editable per-member role prompts from the team pane. Coordinator and member roles shipped in 0.5.0.
- **Console history**: recall past queries per connection.

## Shipped in 0.7.0

- Team protocol v2: coordinator reviews every delivery in the owner's worktree ('approved' or 'rework', two rounds then escalate to the user), tasks live in a shared backlog and free members claim the next ones themselves, done agents park themselves with a 'sleep' control message.
- Board history: 'archive <summary>' snapshots a finished demand into history/ and resets the board, keeping decisions.
- Members roster with worktree paths (members.md), refreshed on join, leave, rename and exit.
- SwiftTerm 1.14: scrollback stays where you put it while agents stream, wheel reaches the CLI when it asks for the mouse, Shift+wheel and Shift+drag stay local, Cmd+click opens links.
- Privacy mode: one toggle narrows sidebar, menu bar and notch to the current project's organization.
- Sidebar drag reordering for projects and organizations.

## Shipped in 0.6.0

- Team message box: talk to the agent team from the team pane as 'user'.
- Rename agents: give a terminal a human name from the context menu; teams address it by that name.
- Stack layout: tab strip on top, one terminal expanded, the rest collapsed but alive.
- Single main window: a duplicate window stole the terminal views (dead scroll, blank cards).
- Configure a running agent from the context menu: model, effort and a standing role (persona).
- Notch glance 2.0: wider bar with a live event ticker and ember gradient, expanded panel with session rows and a timeline.
- Grok CLI as a built-in agent with session resume.
- Notch border beam (grok.com/build style traveling ember) and an active/total agent counter.
- Near-zero idle work: git stat polling pauses while the window is hidden and skips frozen or hibernated sessions; pane refresh loops pause when occluded.

## Later

- **Notch actions**: answer plans, questions and permission prompts without leaving the notch.
- **Usage limit windows**: rate-limit windows and monthly spend per agent, where the CLI exposes them.
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
