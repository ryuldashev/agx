# 0002 — Agent failover: model ladder, then hand the task to another agent

Status: accepted 2026-09-11 (Ruslan: "в таких ситуациях agx переключал агента на другую модель
наилучшую, а дальше — продолжал задачу с другим агентом").

## Context

A Claude Code pane stops dead on `You're out of usage credits. Run /usage-credits to keep using
Fable 5.1 or /model to switch models.` The user has to notice, type `/model`, pick one, and type
"continue". With 30 panes open that is the failure mode of the whole setup: work stalls silently in
background workspaces. The same shape recurs for the weekly/session account limit, expired login, 529
Overloaded, and an agent process that simply dies mid-turn.

Facts that shaped the design:

- The `Stop` hook does **not** fire on an API-error turn (checked in `~/.claude/projects/*.jsonl`:
  `isApiErrorMessage: true` records have no matching Stop). The `StopFailure` hook does, with `error`
  (`rate_limit` / `overloaded` / `authentication_failed` / …), `error_details`,
  `last_assistant_message`, `transcript_path`, `cwd`. Its exit code and output are ignored.
- `rate_limit` covers both "one model's pool is spent" and "the account is out"; only the message
  text tells them apart ("out of usage credits … keep using X" vs "hit your weekly limit").
- `/model <alias>[1m]` switches immediately and saves that model as Claude Code's default for new
  sessions.
- The other connected agent (Codex, `agx spawn --agent codex`) takes a brief as its first message
  through `ScheduledLaunch.commandLine`, the path scheduled sessions already use.
- A dead agent process shows up as the main pane exiting; `AgentIndicator.status == .active` at that
  moment means it died mid-turn (any keystroke or interrupt clears the status first).

## Decision

**Two stages, decided host-free, acted on in the app.**

1. **Model ladder inside the same pane.** `modelExhausted` → the next entry of
   `failoverModels` (default `opus[1m]`, `sonnet[1m]`) whose family (fable/opus/sonnet/haiku) is not
   already exhausted in this session; the app types `/model <entry>` and, 2.5 s later, the continue
   prompt. The session keeps its context, cache and history.
2. **Handoff to another connected agent.** Ladder spent, account limit, auth/billing error, a crash
   (`processExited`), or `--handoff` → a new session `<name> → <agent>` in the same workspace and cwd,
   running the configured handoff agent (default: the first connected agent whose binary differs from
   the failed one) with a brief: reason, source session, transcript path, last three user prompts and
   the last assistant text, digested from the tail of the Claude JSONL. Transient errors
   (`overloaded`, `server_error`, other `rate_limit`) re-prompt after 20 s, at most three times in
   30 minutes, then hand off. `invalid_request`/`max_output_tokens` only notify.

Signal path: `StopFailure` hook → `agx-agent-failure.sh` → `agtermctl session failure <error>
--message … --transcript …` → `ControlDispatcher+Failover` → `ControlServer+Failover` →
`AgentFailoverCoordinator.report`. Crash path: `handlePaneExit` → `paneExiting`. Every action posts a
notification, a `failover` control event, and the session node's `failover` read-back.

Rejected: scanning the terminal buffer for the error text (fragile, racy with the user typing, and
blind to the error type); switching the model in `settings.json` (Claude Code re-reads it only at
launch); keying on the `Stop` hook (it never fires here).

## Consequences

- The hook must be installed (Help ▸ Install Agent Status Hooks re-merges `~/.claude/settings.json`);
  without it only the crash path works. Sessions started before the app restart that shipped this
  never report — the old app rejects `session.failure` as unknown.
- The ladder mutates the user's Claude Code default model. The notification says which model the
  pane now runs so the user can `/model` back.
- A handoff session is a fresh agent: it gets the digest, not the context. The brief points at the
  transcript so Codex can read more if it needs to.
- `failover` state is per session and in-memory; a relaunch forgets which families were exhausted, so
  the first failure after a relaunch may retry a spent family once before moving on.
- Retry counts are bounded so a stuck pane can never re-prompt forever.
