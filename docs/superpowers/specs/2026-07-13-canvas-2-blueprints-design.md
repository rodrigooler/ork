# Canvas 2.0: Blueprints mode

The agent canvas trades live mini terminals for minimalist activity cards, animates real message traffic as traveling packets, celebrates completions toward the lead, and hangs a GitHub PR/CI node above the coordinator. Terminals stay one click away: the grid and stack layouts are untouched, and left-clicking a card opens Focus Mode.

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

## Out of scope

Grid, stack, focus mode, the tree topology pane and the FlowView mode picker are untouched. No new dependencies. No GitHub write operations. No draggable node placement (stays on the roadmap).

## Testing

Pure units: `CanvasLayout` with hub, gh JSON parsing, message-kind classifier (done/approved/other), bezier point evaluation, branch-to-member matching. Existing layout tests keep passing with the new card size.
