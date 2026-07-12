# Roadmap

Priorities for ork, in order. Items move up or down based on real usage; open an issue if something here matters to you.

## Next (0.11)

- **Notch actions**: answer plans, questions and permission prompts without leaving the notch.
- **Usage limit windows**: rate-limit windows and monthly spend per agent, where the CLI exposes them.
- **Tool timeline on session cards**: the notch shows it since 0.10.0; cards next.
- **MCP bridge beyond claude**: other CLIs as they grow per-invocation MCP config flags.

## Shipped in 0.10.1

- Sessions whose worktree directory disappeared (pruned outside Ork, disk cleanup) no longer respawn into a blank dead card: they are dropped at restore with an event note, a failing cd now explains itself in the terminal, and pruning a worktree from the git pane closes the sessions living in it first.

## Shipped in 0.10.0

- MCP bridge for teams: claude sessions get an `ork` MCP server (team_send, team_board, team_members) and message teammates through tool calls instead of shell echoes. A per-session bridge file keeps join-after-spawn and renames working without a CLI restart; other CLIs keep the echo protocol.
- Agent tool timeline: the expanded notch shows each claude session's latest tool call, read from the transcript tail.
- Custom team roles: a pencil chip per member in the team pane edits the standing role, applied to the live terminal and kept for future briefings.
- Console history: both query consoles record every run per connection and recall past queries from a history menu.

## Shipped in 0.9.0

- Quiescence-gated delivery: team messages wait until the recipient's process group is CPU-quiet before being typed into its PTY, so text stops getting swallowed by TUI repaints mid-turn. Identical repeats within a minute deliver once.
- Orphaned-task alert: a member leaving or exiting with open board tasks flags the ids to the coordinator. A watchdog nudges owners once after 30 minutes without done or blocked.
- Protocol v3.2: backlog dependencies with '(after <id>)', a team artifacts/ dir for payloads too big for a message, and an integration gate (coordinator pushes and opens one PR per approved task with `gh pr create`).
- Kanban strip in the team pane: Backlog, In progress and Done columns with counts above the raw board.
- Agent canvas: the flow view's canvas mode draws the team as a card tree with live mini terminals, a crown on the coordinator and a pulse on message routes.
- Session cards show commits behind base (needs rebase) next to the ahead chip.
- Auto-hibernate: optional, a session frozen for 30 minutes ends its process and resumes the conversation on click.
- Usage by project: the usage card breaks the token total down per project directory.
- Kilo Code as a built-in agent, plus official icons for Grok and Kilo Code.

## Shipped in 0.8.1

- Sessions spawn in an interactive login shell: launched from Finder, Ork.app inherits a bare PATH and `~/.zshrc` exports were skipped, so every agent died instantly with "command not found".
- Closing a terminal now leaves its team properly: teammates get the leave note and members.md drops the ghost.

## Shipped in 0.8.0

- Team protocol v3: a standing protocol.md next to the board so agents recover the messaging recipe after context compaction, a coordinator that never implements and decomposes the whole demand before assigning, a real review gate (read the diff, run build and tests, check every done-criterion, hunt edge cases and security holes), and a no-acknowledgement message economy.
- Rebrief button in the team pane: push protocol updates to a live team without disbanding it.
- In-app updates: ork checks GitHub on launch and a sidebar button swaps the app in place and relaunches.
- Real Ork.app bundle with a Finder icon, plus a curl installer (install.sh) into /Applications.
- User messages to the team are exempt from the agent char cap, and failed user deliveries surface in the event feed instead of vanishing.

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

- **Observability pane**: Loki queries, Tempo traces, Grafana links and OpenTelemetry status per project.
- **Queue endpoints**: RabbitMQ and Kafka reachability and basic inspection in the data pane.
- **Draggable flow canvas**: free node placement plus live agent status parsed from the terminal stream.
- **Notarized releases**: Developer ID signing and notarization, native notifications instead of osascript. The `.app` bundle and Finder icon shipped in 0.8.0, ad-hoc signed.
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
