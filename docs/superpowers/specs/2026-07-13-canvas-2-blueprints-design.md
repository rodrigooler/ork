# Canvas 2.0: Blueprints mode, team chat and data hygiene

The agent canvas trades live mini terminals for minimalist activity cards, animates real message traffic as traveling packets, celebrates completions toward the lead, and hangs a GitHub PR/CI node above the coordinator. Terminals stay one click away: the grid and stack layouts are untouched, and left-clicking a card opens Focus Mode. The team pane's raw message log becomes a Discord-style chat, and accumulated team data (log, board) gets automatic and per-round cleanup.

## Context and verified facts

- `TeamService.onRoute` already carries sender and recipient session ids for every routed message; only the recipient pulses today. Message content is structured by protocol shapes (`task <id>`, `done <id>`, `approved <id>`, ...), so classifying a completion is reading the first word, not a heuristic.
- Focus Mode is a global overlay in RootView driven by `store.focusModeSessionID`; opening it from a card is one assignment.
- Session telemetry (last tool call, output tokens, model) exists since 0.11.0 with incremental transcript reads; claude sessions only.
- The app never calls `gh` itself; only agents do. `api.github.com` is occasionally unreachable from Brazil (ANATEL IP block), so any GitHub polling must time out fast and fail silent.
- Canvas 1.0 lesson: the user rejected synthetic activity (SpriteKit constellation) in favor of real content. Cards therefore keep showing real activity (tool call, task, tokens); animation happens only when a real message travels.

## Cards

`AgentCanvasCard` drops `TerminalSurface` and shrinks to about 260x132. Header: agent icon, display name, crown on the coordinator, status dot. Body: live last tool call (claude sessions), current board task (from TeamService task tracking), output tokens. Footer: branch and short model name. Telemetry refreshes every 2.5s only while the canvas is visible. Non-claude sessions show status, task and branch only. Left-click sets `focusModeSessionID`; the existing overlay does the rest. Exited/hibernated cards keep the dimmed treatment.

## Packets

`onRoute` gains the message content: `(senderID, recipientID, content)`. Each routed message spawns a one-shot glowing dot that travels the sender-to-recipient curve in about 0.8s (cubic bezier evaluated at t, pure function, testable) and disappears. Peer-to-peer messages that do not follow tree edges get a temporary curve drawn only for the flight. No standing animation: the canvas costs nothing while the team is quiet. Reduce Motion falls back to the current static highlight.

## Completion glow

Content starting with `done <id>` routed to the coordinator: the packet is golden and slightly larger, and on arrival the lead card flashes a golden ring that decays over about 1.2s. `approved <id>` from the coordinator flashes a moss ring on the member card. Both one-shot, both skipped under Reduce Motion.

## GitHub node

New `GitHubService` polls `gh pr list --state open --json number,title,headRefName,url,statusCheckRollup` in the workspace directory every 60s, only while the canvas is visible, with a short process timeout. On failure (gh missing, unauthenticated, network block) the poll fails silently: the node keeps showing the last good snapshot, or stays hidden if no poll ever succeeded. The node renders above the coordinator, connected by a dashed edge: one row per open PR with number, truncated title, CI dot (green passing, red failing, orange pending) and the owning member badge (headRefName matched to session worktree branches). Clicking a row opens the PR in the browser. `CanvasLayout` grows a hub position as a pure function. The node appears only when a team coordinator exists and PR data is available.

## Zoom

Trackpad pinch (`MagnifyGesture`) scales the canvas between 0.5x and 1.5x; double-click on the background resets to 1x. Scroll pan stays as is.

## Member colors

Sessions of the same agent share one tint, so an eight-claude team renders eight identical coral cards. A deterministic palette (`MemberPalette`: stable hash of the member name into 10 distinguishable hues) colors chat avatars, sender names, canvas card accents and packets, so members are tellable apart everywhere.

## Team chat (Discord style)

Verified data: `log.md` is structured and parseable. Entries start with `- [HH:MM:SS] `; message entries are `sender → recipient: content`, other entries are system events (joined, went idle, control notes); indented `  (...)` lines annotate the previous entry (bounced, spilled, undelivered); any other line continues the previous entry's content.

The team pane's Messages panel becomes a chat rendered from the same file: avatar (initials on the member color, status dot from the live session), colored sender name, recipient chip when the message is directed, timestamp, content, annotations as faint footnotes. Consecutive entries from the same sender collapse under one avatar. System events render centered and faint. The list auto-scrolls to the newest message. The existing composer stays. Member chips in the strip grow the avatar, the standing role and model/effort chips; `configureAgent` starts persisting model and effort on the session (today only persona persists), and claude sessions show the live transcript model when available.

## Data hygiene

Verified data: a real team accumulated 208KB of log across eight sprints; the `archive` control exists since 0.9.0 but no coordinator ever used it (no history/ dir on disk).

- Log rotation, automatic and agent-free: when `log.md` grows past 150KB, Ork moves everything but the newest 200 lines to `history/log-<timestamp>.md`. Ork writes the log, so Ork rotates it; no protocol change, no tokens.
- Per-round board archiving becomes part of the integration gate: after the demand's PR lands or the user accepts the demand, the coordinator must send `archive <summary>` (existing control: board snapshots to history/, working sections reset, `## Decisions` survives).
- An "Archive board" button in the team pane gives the user the same control manually, with a confirmation since it resets the live board (everything lands in history/ first, nothing is lost).

## Out of scope

Grid, stack, focus mode, the tree topology pane and the FlowView mode picker are untouched. No new dependencies. No GitHub write operations. No draggable node placement (stays on the roadmap).

## Testing

Pure units: `CanvasLayout` with hub, gh JSON parsing, message-kind classifier (done/approved/other), bezier point evaluation, branch-to-member matching, chat log parsing (messages, system events, annotations, continuations), member palette stability, log rotation (threshold, tail kept, archive written). Existing layout tests keep passing with the new card size.
