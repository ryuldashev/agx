# 2026-09-15 — auto-answer (`session.autoanswer`, blocked prompt answered after a grace)

Branch `auto-answer-2026-09-15` off `agent-failover-2026-09-11` at `639180d` (the deployed v0.24.0 line;
`origin/master` is 14 behind it). ADR: `docs/decisions/0003-auto-answer.md`. Rule text:
`.claude/rules/control-api.md` → "Auto-answer".

## What
A Claude Code / Codex pane goes `blocked` on a permission prompt and nobody answers for 45 s → the app
presses the affirmative key itself (Claude: Return on the highlighted "Yes"; Codex: `y`) through the same
`GhosttySurfaceView.inject` path `session type` uses. A prompt whose visible text carries a destructive
command (`rm -rf`, `git push --force`, `sudo`, `git reset --hard`, `DROP …`, …) is never answered: the
user is notified instead. Every decision posts a desktop notification (answered or held) and an
`auto_answer` event; the session's tree node carries `autoAnswer`. Settings ▸ Agents ▸ Auto-answer
(toggle + delay), `agtermctl session autoanswer on|off|status --target`. `agx spawn --agent codex` now
launches `codex -a on-request -s workspace-write` (the requested `on-failure` no longer exists in codex-cli
0.154 — `-a` takes `on-request|never`; found when the first Codex test pane exited on a parse error).

## Plan (written before the code)
- core `AutoAnswer.swift`: `DestructiveCommand` catalog + `match`, `AutoAnswerPolicy.decide(screen:agent:)`,
  `AutoAnswerState`, `ControlAutoAnswerNode`; `Command.sessionAutoAnswer`; `ControlArgs.mode`
  (`on|off|status`); `ControlResult.autoAnswer`; `ControlEventKind.autoAnswer` + payload `agent`;
  `Session.autoAnswer`; `ControlSessionNode.autoAnswer`; `AppSettings.autoAnswerEnabled/DelaySeconds`.
- app `AutoAnswerCoordinator`: armed from `setSessionStatus` on an idle→blocked transition, fires after
  the delay, re-validates (still blocked, still enabled, agent known, prompt visible on screen, no
  destructive text), injects the key, announces.
- CLI `SessionAutoAnswerCommands.swift`; `formatAutoAnswer`; `events` human line.
- Settings ▸ Agents ▸ Auto-answer section; `SettingsModel.setAutoAnswer*`.
- `scripts/agx`: codex spawn flags.
- docs: skill (SKILL/reference/examples), `site/commands.html#autoanswer`, FORK.md, control-api rule.

## Built
- **agtermCore** `AutoAnswer.swift`: `DestructiveCommand` (catalog of 22 shapes, `match`), `AutoAnswerAgent`
  (affirmative key, prompt markers, `dialogRegion`), `AutoAnswerDecision`, `AutoAnswerPolicy.decide`,
  `AutoAnswerPresence.remainingGrace`, `AutoAnswerHud.spec/owns`, `AutoAnswerState`, `ControlAutoAnswerNode`,
  `ControlAutoAnswerOptions`. `Command.sessionAutoAnswer`, `ControlArgs.mode`, `ControlResult.autoAnswer`,
  `ControlEventKind.autoAnswer` (+ payload `agent`), `Session.autoAnswer`, `ControlSessionNode.autoAnswer`
  (`AppStore.autoAnswerNode` masks `dueAt` unless the session is blocked — a keystroke clears the status
  without reaching the coordinator), `AppSettings.autoAnswerEnabled/DelaySeconds` + `effective*` (delay
  clamped to 5…600), `AppStore.autoAnswerEnabled/DelaySeconds`, `AppStore.idleSeconds`,
  `ControlDispatcher+Failover.swift` → `dispatchAutoAnswerCommand`.
- **agtermctlKit**: `SessionAutoAnswerCommands.swift` (`session autoanswer [on|off|status]`),
  `formatAutoAnswer`, `events` human line for `auto_answer`.
- **app**: `AutoAnswerCoordinator.swift` (arm on idle→blocked from `setSessionStatus`; UUID token per
  session so a stale fire is a no-op; `DispatchQueue.main.asyncAfter`, no Timer/`assumeIsolated`; countdown
  HUD top-right redrawn every 5 s, own HUD only; presence check `NSApp.isActive` + frontmost window +
  active session, grace re-armed for `delay - idleSeconds`; screen read from the blocked pane (left/right
  by `statusPane`, scratch never); `inject(text:)`; notification + event),
  `Control/ControlServer+AutoAnswer.swift`, `AppActions.autoAnswer`, `agtermApp.swift` wiring (coordinator
  gets `controlServer` for `paneMetrics`), Settings ▸ Agents ▸ Auto-answer (`AgentsSettingsView`,
  `SettingsModel.setAutoAnswer*` + fan-out to every store like auto-follow).
- **scripts/agx**: `CODEX_SPAWN_FLAGS`, `_agent_launch` (skips when the agent line already carries
  `-a/--ask-for-approval/-s/--sandbox/--full-auto/--yolo/--dangerously-bypass…`), `agx context` line.
- **Tests**: `AutoAnswerTests` (catalog, policy incl. dialog-region cases, presence, HUD, state, node,
  settings, dispatcher + tree masking), `SessionAutoAnswerCommandsTests`. Docs: ADR 0003,
  `.claude/rules/control-api.md` → "Auto-answer", skill (SKILL/reference/examples),
  `site/commands.html#autoanswer`, `FORK.md`.

## Live check (Debug instance, isolated `/tmp/agx-aa`, delay 15 s)
| case | result |
|---|---|
| Claude Write prompt, nobody in the session | `blocked` 01:02:58 → `auto_answer answered agent=claude` 01:03:13, file written |
| Codex `-a on-request -s workspace-write`, cp outside the workspace | escalation prompt → `answered` (y) after 16 s, cp done |
| Codex `rm -rf …` dialog | `held reason=destructive: rm -rf`, "Agent needs you", prompt untouched |
| Claude Write whose diff contains `rm -rf` | `held` (the diff is inside the dialog region — by design) |
| safe prompt with `rm -rf` visible ABOVE the dialog, both agents | `answered` — after narrowing the scan to the dialog; the first cut scanned the whole screen and held here |
| `session autoanswer off` → next prompt | left alone 25 s+; `on` while blocked → `dueAt` set, fired |
| tree while armed | `hud.message = "Auto-answer in 15 s"`, `autoAnswer.dueAt` present; `status` prints `on (settings) 15s due …` |

Codex ran the fizzbuzz brief with no prompt at all (its config allows network), which is the point: only
the escalations reach the user, and now only the destructive ones.

Gotchas met: codex-cli 0.154 has no `-a on-failure` (pane exited on a parse error → `on-request`); a Debug
socket driven from a live agx pane inherits `AGTERM_WORKSPACE_ID` and `agx spawn` fails with "session
creation failed" — `env -u AGTERM_WORKSPACE_ID -u AGTERM_SESSION_ID …`; zsh does not word-split a
`S="--socket …"` string, use an array.

## Not done / next
- The presence rule is unit-tested and traced, not driven live: I cannot be "in" a Debug session from a
  control socket. Watch the first real week for a prompt answered while Ruslan was reading it.
- ~~`AskUserQuestion` dialogs~~ — Ruslan saw one get its first option picked after the deploy. Confirmed
  live (it flips `blocked`, footer has `Esc to cancel`, Return chose "Red"). Fixed the same session: a
  question-to-the-user veto (`Type something.` / `Chat about this`; Codex `Enter to submit`) →
  `held reason=question for the user`, and a permission prompt now needs question + Yes option. Re-verified
  live: question held, the next Write prompt answered.
- Claude's dialog region keys on a rule/box line; a Claude Code release that changes that chrome falls
  back to whole-screen scanning (more holds, never more answers). No UI test drives the real dialog.
- Counters and the per-session override are in-memory; a relaunch forgets them.
- Codex's session-start hook printed `hook returned invalid session start JSON output` in the Debug
  instance — pre-existing, unrelated to this feature, not chased.
