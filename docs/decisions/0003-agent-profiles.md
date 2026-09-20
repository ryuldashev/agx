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

One folder per agent, `agterm/Resources/agent-status/agents/<binary>/`, is the single place agx knows
an agent. Its `agent.json` declares: `seedFlag` (where `"$b"` goes), `resume` (`{id}`), `context`
(`sessionStartHook` / `briefPrefix`), `configDirectory` (the install gate), `trust` (the folder-trust
file `agx spawn` probes) and `status` — discriminated by `kind`: `jsonHooks` (file + `claude`/`cursor`
dialect + bindings), `tomlHooks` (file + adapter script + event→action rows), `plugin` (source,
destination, `requires` directory, ownership marker). An agent that needs code keeps it in the same
folder (`codex/status.sh`, `opencode/plugin.js`, `pi/extension.ts`); the shared scripts stay at the
package root.

`AgentCatalog.known` decodes the manifests (`AGTERM_AGENTS_DIR` → the bundle → the source checkout);
`scripts/agx` reads the same files in python. Consumers read a profile and never a binary name:
`AgentHooksInstaller` runs one step per manifest by `status.kind`; `ScheduledLaunch.commandLine`
(schedule + failover handoff) renders the seed; `AgentBinary.of` resolves through the catalog; the two
session-start scripts take `--resume-line` / `--format` from the binding. The core knows the three
integration kinds and nothing about any agent — adding one is a folder, not a Swift change.

Graceful floor: a manifest with only `name` and `binary` is launch-only — positional seed, no glyph, no
resume, `agx spawn` prefixes the brief with a pointer to `agx context`. Nothing an unknown CLI can
do today is taken away from it. A malformed manifest is skipped, not fatal; `AgentCatalogTests`
asserts every bundled one decodes and that every script it names exists.

Refined the same day from a first cut that kept the profiles as Swift literals plus a python mirror
table: two copies of the same facts, and Cursor hooks installed on documentation alone. The manifest
layout removes the mirror; Cursor and Mimo ship launch + resume until a live pane confirms their hooks.

## Consequences

- Adding an agent = `agents/<binary>/agent.json` (+ its adapter beside it) + a
  `docs/reference/agents/<binary>.md` of measured facts. A new trust-file format needs a probe in
  `scripts/agx:TRUST_PROBES`; a new hook-file format needs a fourth `status.kind` in the core.
- Installed Claude hooks from before this change carry no `--resume-line`/`--format`; the idempotency
  probe is by script path so they are kept as-is, and both scripts default to Claude's lines.
- Gemini's `Notification` matcher is installed on a documented contract, not on an observed run (needs
  a login this machine does not have). If it misfires, the manifest is the only place to fix.
- Cursor and Mimo have no `status` until a live pane confirms their hook surface; Mimo's plugin
  loading is unverified.
- Codex re-prompts hook trust once: its adapter moved from `agterm-codex-status.sh` to
  `agents/codex/status.sh`, and Codex trusts hooks by command path.
- `agx usage` remains Claude-only (Codex exposes usage only over its app-server JSON-RPC).
