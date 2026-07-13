# Ork Manager, message auto-spill and autopilot

Design for three team features, built in this order because each uses the previous one.

## Context and verified facts

- The 1200 char message cap never truncates: over-cap agent messages bounce back to the sender with instructions (user messages are exempt). The failure mode is fidelity loss when the sender re-summarizes, plus a wasted round trip.
- Members already message each other directly; routing is per recipient through outbox files. Broadcast-and-ignore would multiply token cost by team size, so it is rejected. What is missing is protocol wording that encourages direct peer questions.
- Lesson from the Paperclip field notes: an approval gate implemented as a CLI permission prompt hangs autonomous agents, because nothing answers it. Root approval must be Ork-mediated (UI), never a CLI prompt.

## Phase 1: message auto-spill

Instead of bouncing over-cap agent messages, Ork saves the full text to the team's `artifacts/msg-<sender>-<millis>.md` and delivers a short envelope with the absolute path. Nothing is ever cut or lost; the PTY injection stays small; no round trip. The bounce path remains only for unknown recipients. The protocol text explains the spill and adds: technical questions go directly to the teammate who owns the code; copy the coordinator only when scope or schedule changes.

## Phase 2: Ork Manager

A manager is a normal claude session whose MCP bridge file carries `"manager": true`. The ork-mcp server then exposes orchestration tools on top of the team tools:

- `ork_project_info`: workspace name, directory, current team roster with roles.
- `ork_spawn_member(name, agent, role, model, effort)`: spawn a session in the workspace, join it to the team, apply persona.
- `ork_configure_member(name, role, model, effort)`: reconfigure a running member.
- `ork_disband_member(name)`: close a member session.

Every mutating tool goes through a root approval gate: the server writes a request file under `Application Support/Ork/mcp/requests/<id>.json` and waits; Ork watches the directory, shows the request (action summary) for approve or deny, and writes the response file. The tool returns the outcome to the manager. Timeout counts as denied.

UI entry: a "Spawn manager" action in the team pane spawns the manager with a briefing that explains the tools and the approval gate. The user then talks to it: "build a team for this project: coordinator, four engineers, two QA, one cloud, one LGPD, one fintech" and the manager reads the repo, designs roles and personas, and calls the tools.

## Phase 3: autopilot

A standing team improves the project continuously, gated twice:

- The autopilot coordinator writes proposals to `team/<ws>/proposals/<id>.md` (title, rationale, scope, estimated size). Ork surfaces open proposals in the team pane; approve turns the proposal into a board task via the normal flow, reject archives it with a note back to the coordinator.
- Implementation follows the existing review and integration gates (one PR per approved task), so the PR is the second root gate.

A cycle timer (configurable, default 30 min) sends the coordinator a "cycle" control message. Before each cycle Ork checks the 5h usage window from LimitsService against a configurable ceiling; above it, the cycle is skipped and the event feed says so. Learnings persist in `team/<ws>/learnings.md`, included in briefings, so cycles inherit what earlier cycles discovered. Any agent CLI can be the autopilot brain; hermes or others enter through agents.json as custom agents, no code change.

## Testing

Phase 1: spill file contract, envelope delivery, user exemption. Phase 2: request/response file protocol, approval and denial and timeout paths, tool gating by bridge flag. Phase 3: proposal parsing, cycle skip above ceiling.
