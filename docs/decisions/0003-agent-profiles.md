# 0003 — Agent profiles: one catalog entry per CLI, nothing else names an agent

Status: accepted 2026-09-11 (Ruslan: "agx должен стать agent agnostic, при этом хорошо знать каждый
агент и глубоко интегрирован с ним быть, с его командлайном как минимум… не сломай то что работает,
graceful degradation нормально").

## Context

agx could *launch* fifteen agent CLIs (`AgentCatalog.known`) but *understood* one: every live
integration — the status glyph, `claude --resume` after a relaunch, `agx context` on session start,
the trust probe before a seeded brief, `agx usage` — was a Claude branch in a different file
(`AgentHooksInstall.claudeHooks`, `agx-session-restore.sh`, `agx-session-context.sh`,
`scripts/agx:_agent_trusts`, `ScheduledLaunch.commandLine`'s `exec <agent> "$b"`). Codex had half of
it through its own adapter; Gemini, Cursor, OpenCode, Mimo were a pane with a terminal in it.

Measured (2026-09-11, `docs/reference/agents/*.md`): Gemini CLI's hooks are a port of Claude Code's
(`gemini hooks migrate` exists) with `-i` for a seeded interactive prompt and `-r <id>` to resume;
Cursor has `~/.cursor/hooks.json` in a flat `{version, hooks}` dialect, `--resume <id>`, and no
permission event; OpenCode and its fork Mimo read the positional as a project dir and take
`--prompt`, resume with `--session`; Codex's `SessionStart` stdin carries `session_id` and accepts
`hookSpecificOutput.additionalContext`. Antigravity is an IDE with an internal RPC client, not a
terminal agent — out of scope.

## Decision

`AgentProfile` (`agtermCore/AgentCatalog.swift`) is the single place agx knows an agent: `seed`
(where `"$b"` goes), `resumeTemplate` (`{id}`), `status` (`.jsonHooks(file, shape, bindings)` /
`.codexConfig` / `.piExtension` / `.opencodePlugin` / `.none`), `context` (`.sessionStartHook` /
`.briefPrefix`) and `configDirectory` (the install gate). Consumers read the profile and never a
binary name: `AgentHooksInstaller` iterates every `.jsonHooks` profile through one
`mergeJSONHooks(shape:)`; `ScheduledLaunch.commandLine` (schedule + failover handoff) renders the
seed; `AgentBinary.of` resolves through the catalog; the two `SessionStart` scripts take
`--resume-line` / `--format` from the binding instead of hard-coding Claude; Codex's adapter calls
them from `session-start`.

Graceful floor: a profile with only a name and binary is launch-only — positional seed, no glyph, no
resume, `agx spawn` prefixes the brief with a pointer to `agx context`. Nothing an unknown CLI can
do today is taken away from it.

`scripts/agx` (python) cannot read the Swift catalog, so it carries a mirror `AGENTS` table for seed,
context delivery and trust probes. Accepted duplication, documented in both places; the alternative
(a control command exposing profiles) is more plumbing than the table until a third consumer appears.

## Consequences

- Adding an agent = one `AgentProfile` + a `docs/reference/agents/<binary>.md` of measured facts (+ the
  `AGENTS` mirror line in `scripts/agx` when seed/context/trust differ from the default).
- Installed Claude hooks from before this change carry no `--resume-line`/`--format`; the idempotency
  probe is by script path so they are kept as-is, and both scripts default to Claude's lines.
- The Cursor `sessionStart` hook and Gemini's `Notification` matcher are installed on documented
  contracts, not on an observed run (both need a login this machine does not have). If either
  misfires, the profile is the only place to fix.
- Mimo's plugin loading is unverified; its status stays `.none` until measured.
- `agx usage` remains Claude-only (Codex exposes usage only over its app-server JSON-RPC).
