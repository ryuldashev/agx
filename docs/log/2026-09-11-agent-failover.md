# 2026-09-11 — agent failover (`session.failure`, model ladder, handoff to Codex)

Branch `agent-failover-2026-09-11` off `reader-pane-2026-09-10` (which is still unmerged and 5 ahead of
`origin/master`). ADR: `docs/decisions/0002-agent-failover.md`. Rule text: `.claude/rules/control-api.md`
→ "Agent failover".

## What
When a Claude Code pane stops on an API error the app now acts instead of the user: a spent model pool
types `/model <next>` (ladder `opus[1m]`, `sonnet[1m]`) and "continue"; an account limit, auth error,
spent ladder, or a crashed agent opens `<name> → Codex` beside it with a brief from the transcript;
529/overload re-prompts after 20 s (≤3). Notification + `failover` event + `tree` read-back each time.

## Built
- **agtermCore** `AgentFailover.swift`: `AgentFailure.classify`, `ModelFamily`, `FailoverAction`,
  `FailoverState`, `FailoverPolicy.decide/advance`, `AgentBinary.of`, `ClaudeTranscript`
  (transcriptPath, sessionID(fromRestoreCommand:), digest), `HandoffBrief.compose`,
  `ControlFailoverNode`, `ControlFailureOptions`. `Command.sessionFailure`, `ControlArgs.error/
  transcript/handoff`, `ControlResult.failover`, `ControlEventKind.failover` (+ payload
  `action/model/reason/source`), `Session.failover` + `agentTranscriptPath`, `ControlSessionNode.failover`,
  `AppSettings.failover*` + `effectiveFailover*` + `failoverHandoffAgent(for:)`,
  `ControlDispatcher+Failover.swift`, `AgentHooksInstall` StopFailure hook entry.
- **agtermctlKit**: `SessionFailureCommands.swift` (`session failure`), `formatFailover`, `events`
  human line for `failover`.
- **app**: `AgentFailoverCoordinator.swift` (report / paneExiting / switchModel / retry / handoff /
  announce), `Control/ControlServer+Failover.swift`, `AppActions.failover`, `agtermApp.swift` wiring
  (`makeSurface` gets `actions`; `handlePaneExit` calls `paneExiting` before closing the primary pane),
  `Resources/agent-status/agx-agent-failure.sh` (StopFailure hook; baked `AGTERMCTL`),
  Settings ▸ Agents ▸ Failover section (`AgentsSettingsView`, `SettingsModel.setFailover*`).
- **Tests**: `AgentFailoverTests` (classify, policy, transcript, dispatcher), `SessionFailureCommandsTests`,
  `AgentHooksInstallTests` (6 hooks, StopFailure). Docs: skill (SKILL/reference/examples),
  `site/commands.html#failure`, `FORK.md`, `scripts/agx` manifest.

## Not done / next
- The hook is only live after Help ▸ Install Agent Status Hooks from the NEW app (or a manual merge of a
  `StopFailure` entry pointing at `~/.config/agx/agent-status/agx-agent-failure.sh`). Sessions running
  under the old app never send `session.failure`.
- No UI test drives a real `/model` switch — the typing path is `GhosttySurfaceView.inject`, verified
  by `session type` coverage, not by a failover-specific XCUITest.
- Exhausted families are in-memory per session; nothing persists them across a relaunch.
- Handoff brief is a digest (3 prompts + last answer). If Codex needs more, it reads the transcript path
  in the brief.
