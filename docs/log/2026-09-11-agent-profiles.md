# 2026-09-11 — agent profiles: agx becomes agent-agnostic through one catalog

Branch `agent-profiles-2026-09-11` off `agent-failover-2026-09-11` (unmerged, 7 ahead of
`origin/master`). ADR: `docs/decisions/0003-agent-profiles.md`. Reference: `docs/reference/agents/`
(claude/codex/gemini/cursor/opencode/mimo — measured against installed CLIs; gemini and cursor-agent
were installed for this).

## What
`AgentProfile` replaces `KnownAgent`: seed flag, resume template, status integration (JSON hooks with a
Claude or Cursor dialect / Codex TOML / Pi / OpenCode plugin / none), context delivery, config dir.
Gemini CLI and Cursor gain status hooks + resume pin + `agx context` on session start; Codex gains resume
pin + context through its adapter's `session-start`; OpenCode and Mimo seed with `--prompt` and resume
with `--session`; the OpenCode plugin pins `--session <id>` on `session.created`. `agx spawn` seeds per profile, prefixes the brief with an `agx context` pointer for
agents without a hook, probes Gemini/Mimo folder trust, and lists the installed agents in `agx context`.

## Verified
`swift test` 2778/2778, `make lint` clean, hook scripts exercised against a fake `agtermctl`/`agx`
(restore lines for claude/gemini/cursor/codex, bad id refused, three context envelopes).

## Next
- Gemini `Notification` matcher and Cursor `sessionStart` are on documented contracts — watch the first
  real pane of each; the profile is the only place to adjust.
- Mimo: check whether `~/.config/mimocode/plugins/` loads the OpenCode status plugin; if yes, flip its
  status to `.opencodePlugin` with a mimo path.
- `agx usage` for Codex via `account/usage/read` on the app-server.

## Later the same day — per-agent folders
Ruslan set the bar: open-source quality, one folder per agent with its hooks, nothing extra. Restructured:
`Resources/agent-status/agents/<binary>/agent.json` (16 manifests, the schema is in ADR-0003) with the
agent's adapter beside it (`codex/status.sh`, `opencode/plugin.js`, `pi/extension.ts`); `AgentCatalog`
is now a loader, `AgentHooksInstall(er)` is generic over `jsonHooks`/`tomlHooks`/`plugin`, `scripts/agx`
reads the same manifests (the python `AGENTS` mirror is gone). Trimmed Cursor and Mimo to launch +
resume — their hooks were installed on docs, not on a run. Plugin/extension defaults now point at
`~/.config/agx/…` (they said `agterm`, masked here by a symlink).

Verified: `swift test` 2785/2785, `make lint` clean, `make test-app` 266/266, `make build`, `make deploy`.

Next: relaunch agx + Help ▸ Install Agent Status Hooks (Codex asks for hook trust once — its adapter path
changed). First live Gemini pane confirms the `Notification` matcher; first live Cursor pane earns its
`status` block.
