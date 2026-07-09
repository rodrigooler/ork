# Roadmap

Priorities for ork, in order. Items move up or down based on real usage; open an issue if something here matters to you.

## Next (0.5)

- **Query consoles**: run queries against the registered Postgres (PostgresNIO) and Redis (RediStack) endpoints from the data pane.
- **Config file driven agents**: define custom agents in a config file instead of editing `Models.swift`.
- **Worktree janitor**: list, diff, merge and prune session worktrees from the UI.

## Later

- **Observability pane**: Loki queries, Tempo traces, Grafana links and OpenTelemetry status per project.
- **Queue endpoints**: RabbitMQ and Kafka reachability and basic inspection in the data pane.
- **Draggable flow canvas**: free node placement plus live agent status parsed from the terminal stream.
- **Proper `.app` bundle**: signed and notarized releases, real app icon, native notifications instead of osascript.
- **Notch on external displays**: the glance panel only attaches to the built-in screen today.
- **Scrollable terminal grid**: keep cells usable past six concurrent sessions.

## Shipped in 0.4.0

- Workspaces with organization grouping.
- Agent sessions for Claude Code, Codex, OpenCode, Gemini CLI and plain shells.
- Worktree isolation per session.
- Session persistence across relaunches, resuming the agent conversation where the CLI supports it.
- Idle freeze: sessions idling for ten minutes are suspended with SIGSTOP and wake on interaction.
- Focus mode, flow view, usage dashboard, menu bar companion, notch glance panel.
- Data pane with Postgres and Redis reachability probes.
