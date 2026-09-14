# 0003 — Auto-answer: a permission prompt nobody answers gets a Yes from the app

Status: accepted 2026-09-15 (Ruslan: "сессия ушла в blocked на permission-промпте и юзер не отвечает
45 с → приложение само вводит Да … деструктивные команды → только notify"; then: "оно должно с
человеком сосуществовать … дать мне время … если пользователь не заходит в сессию или не шевелится …
то бы я как-то предупреждал бы").

## Context

With many agent panes open, the one that matters most is often the one sitting on `Do you want to
proceed?` in a background workspace. Claude Code's hook and Codex's footer watcher already flip the
session to `blocked`, the sidebar glyph changes, a notification goes out — and then nothing happens
until the user finds the pane. A permission prompt on an ordinary edit or command is noise for most
briefs; the only prompts worth a human are the destructive ones.

Facts that shaped the design:

- `blocked` is the existing, agent-agnostic detection: Claude Code's `Notification` hook
  (`permission_prompt`) and Codex's footer watcher both land in `session status blocked`. Any
  keystroke in the pane clears it (`GhosttySurfaceView.keyDown`); `inject(text:)` — what
  `session type` uses — does not, so the app's own answer leaves the status to the agent's next hook.
- Claude Code's dialog is a list with "Yes" highlighted, so a single Return picks it; Codex's approval
  overlay binds `y`. Both are one key event, not a paste, so the paste detection that swallowed the
  failover prompt's Return (ADR 0002) does not apply.
- Neither agent tells the app WHAT it is asking. Claude Code's `PermissionRequest` hook does, but it is
  Claude-only, and Codex has no equivalent that fires before its approval overlay. The visible text of
  the pane is the one ground truth both agents share — it is exactly what the user would have read.
- codex-cli 0.154 accepts `-a on-request|never`; `on-failure` (the flag the request named) is gone.
  Under `-s workspace-write` a write outside the workspace or a blocked network call makes the model
  request escalation, which is the approval prompt this feature answers.
- A pane the user is looking at is different from a background one. The user may be reading the
  diff; answering over them is worse than not answering at all.

## Decision

**Detect with the status, decide at fire time from the screen, answer for the user — never over them.**

1. **Arm on `idle → blocked`.** `AutoAnswerCoordinator.statusChanged` (called from `setSessionStatus`)
   starts the grace (Settings, default 45 s, 5…600) for that session; a keystroke, an `active` from the
   hook, or the session closing cancels it. A `blocked` re-asserted over `blocked` is the same episode.
2. **Warn while it runs.** A HUD (`Auto-answer in N s — … any key here keeps it for you`) sits top-right
   over the pane, redrawn every 5 s. It uses the session's overlay slot: a caller's program there wins,
   a foreign HUD is never replaced, and only the feature's own HUD is closed.
3. **Presence rule.** At fire time, if the session is the selected one in the frontmost window of the
   active app (`NSApp.isActive`, `frontmostWindowID`, `activeSession`) the grace counts from the user's
   last input in that window (`AppStore.idleSeconds`, the auto-follow signal): still moving → re-arm
   for the remainder. Anywhere else the plain grace applies. `AutoAnswerPresence.remainingGrace` is the
   pure rule.
4. **Decide from the dialog text.** `AutoAnswerPolicy.decide(screen:agent:)`: unknown agent
   (`AgentBinary.of` says neither claude nor codex) → hold; pane not readable → hold; no prompt marker
   on screen (`Do you want to`, `1. Yes` / `Would you like to run`, `Press enter to confirm`, …) →
   hold; a `DestructiveCommand` in the dialog region → hold `destructive: <name>`; else answer. The
   region is the open dialog (Codex: from its question; Claude: from the rule/box line above the tool
   box) to the end of the screen; an unrecognized layout falls back to the whole screen. Holding is
   the cheap error: it costs one manual answer. The catalog is broader than the five named
   (`rm -rf`, `git push --force`, `sudo`, `git reset --hard`, `DROP`): checkout/restore `--`, `clean -f`,
   `branch -D`, `stash drop`, `TRUNCATE`, `DELETE FROM`, `dd of=/dev/`, `mkfs`, `diskutil erase`,
   `chmod/chown -R`, `kill -9`/`killall`/`pkill`, `shutdown`, `launchctl bootout`, service stops,
   `docker rm`, `kubectl delete`, fork bomb.
5. **One key, then hands off.** `inject(text:)` of `\n` or `y`, no repeat: a blind second key could
   answer a second prompt unguarded. Every decision posts a notification (`Auto-answered` /
   `Agent needs you`), an `auto_answer` event (`action`, `reason`, `agent`), and the session node's
   `autoAnswer` read-back (`enabled`, `source`, `delaySeconds`, `dueAt` while armed, counters,
   `lastAction`, `lastReason`).
6. **Controls.** Settings ▸ Agents ▸ Auto-answer (toggle, default on; delay stepper);
   `agtermctl session autoanswer on|off|status --target` sets a per-session override that outlives a
   Settings flip (`source: session`); `off` drops a running grace, `on` while blocked arms one.
   `agx spawn --agent codex` appends `-a on-request -s workspace-write` unless the agent line already
   spells an approval or sandbox flag.

Signal path: agent hook → `session status blocked` → `ControlServer+SessionActions.setSessionStatus`
→ `AutoAnswerCoordinator.statusChanged` → (grace, HUD, presence) → `AutoAnswerPolicy.decide` →
`GhosttySurfaceView.inject` → notification + `auto_answer` event.

Rejected: Claude's `PermissionRequest` hook as the trigger (Claude-only, fires before Codex's overlay
exists, and would split the feature per agent); scanning the buffer to DETECT the prompt (the
existing status rule already forbids it — the status is the detection, the screen is only read once,
at fire time, for the decision); a second Return "to be safe"; a separate arm-time notification
(the HUD is the warning, the `blocked` notification already went out); persisting counters or the
override across a relaunch.

## Consequences

- No hook change: the feature rides the `blocked` status hooks already installed, so sessions
  started under the previous app report to the new one after a relaunch.
- Default ON. Every unattended, non-destructive prompt in every Claude/Codex pane is answered after
  45 s. The user turns it off in Settings or per session; both are read back on the tree.
- The destructive check reads the dialog, not the agent's intent: a Write whose diff contains
  `rm -rf` holds too, and a command the catalog does not know is answered. A miss is bounded by the
  agent's own sandbox (Codex `workspace-write`) and by the prompt itself — the app only ever says
  what the agent asked to do.
- The Claude dialog region keys on a rule/box line; a Claude Code release that changes the dialog
  chrome degrades to whole-screen scanning (more holds, never more answers).
- The presence rule needs the app active and the session on screen; a user watching the pane through
  Screen Sharing or a second display with another app frontmost is "not in the session" and gets the
  plain grace — the HUD is their warning.
- If Claude Code's `AskUserQuestion` dialog flips `blocked`, its options are answers to a question,
  not permissions. The `1. Yes` marker is absent there, so it holds ("no prompt visible") unless an
  option happens to read "Yes". Known gap, acceptable: a hold is a notification.
- `autoAnswer` state is per session and in-memory; a relaunch forgets counters and overrides.
