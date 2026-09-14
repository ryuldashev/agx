# 0003 — Private sessions: never persisted, transcript erased on close

Status: accepted 2026-09-14 (Ruslan: a session for things that must not end up in memory, logs or
the next relaunch).

## Context

Every session agx opens leaves three kinds of trace. The app's own: `workspaces.json`, the window
snapshots, `recent-closed.json`, and (ADR 0001) a detached abduco server that survives a relaunch.
The agent's own: Claude Code writes `~/.claude/projects/<cwd>/<sid>.jsonl` plus a `<sid>/` directory,
a `history.jsonl` line per prompt, `debug/<sid>.txt`, `todos/`, `file-history/<sid>/`,
`session-env/<sid>/`, `tasks/<sid>/`, a per-session scratchpad under `/private/tmp/claude-<uid>/`,
and this Mac mirrors every transcript into `~/claude-archive/projects/` (append-only, by design);
Codex writes `~/.codex/sessions/yyyy/mm/dd/rollout-<ts>-<sid>.jsonl` and `~/.codex/history.jsonl`
lines. The agent's habits: CLAUDE.md tells it to append lessons to amem, call `sessionize-mark`,
and write handoff logs.

Facts that shaped the design:

- The app never learns the agent's session id directly. It arrives only inside the SessionStart
  hook's restore pin (`claude --resume <id> --fork-session`, `codex resume <id>`), and a new id is
  pinned after every `/clear`. Without hooks there is no id and nothing can be erased safely.
- `AppStore.snapshot()` is the single choke point for `workspaces.json` and the window snapshots;
  the recent-closed record is built from the same session snapshot.
- Deleting by glob without an id would take other sessions' files with it. Deleting by exact id
  cannot: every per-session Claude/Codex artefact carries the id in its name.
- A session can close abnormally (crash, force-quit, `kill -9`) with no teardown at all.
- The claude.ai copy of a Claude Code conversation is a server-side record the app cannot reach.

## Decision

- `Session.isPrivate`, set at creation (`addSession(isPrivate:)`, `session.new --private`,
  `agx spawn --private`, File ▸ New Private Session ⌘⇧P) or toggled live (`session.private on|off|toggle`,
  the row's context menu, the palette). The sidebar row shows a lock instead of the terminal icon; the
  window title carries 🔒.
- Private sessions are filtered out of `snapshot()` (workspaces, selection, recency), never recorded
  in recent-closed, and `DurablePane.shouldWrap` returns false for them, so no abduco server exists to
  reattach or to leak the command line.
- Agent session ids are captured on every `session.restore` pin of the main pane
  (`Session.agentSessionTargets`, not persisted). For a private session they are written at once to
  `<stateDir>/private-cleanup.json` (`PrivateCleanupStore`: agx session id + agent + id, nothing else).
- Cleanup (`PrivateSessionCleanup.sweep`, host-free) removes only files whose name is the exact agent
  session id under the known roots, rewrites `history.jsonl` through a temp file and `rename(2)`
  keeping every unparseable line, removes agx's own `~/.claude/agx-usage/<agx id>.json`, and reports
  counts only. No backups: a backup of a private transcript is the thing being avoided.
- `PrivateSessionSweeper` (app) runs the sweep 2 s after a private session is discarded (SIGHUP grace
  for the agent's last writes) and 3 s after launch for every entry still pending (the abnormal-close
  case, after `DurableSpawn.reapOrphans`). An entry is dropped only when nothing failed; a failed
  sweep is retried on the next launch. The outcome goes to the app log and one notification line.
- `agx context` prints a `THIS SESSION IS PRIVATE` block for the agent inside: no amem, no
  `sessionize-mark`, no project docs/logs, no files outside the scratchpad, no non-private spawns.
- The read side: `ControlSessionNode.private` (omitted when false), `tree` tag `(private)`,
  `agx context --json` `private` flag.

## Consequences

- A private session is exactly as private as the hooks make it. Without the SessionStart hook there
  is no session id, and the close notice says so; the transcript then stays wherever the agent put it.
  This branch's bundled `agx-session-restore.sh` pins Claude only; the installed copy in
  `~/.config/agx/agent-status/` already pins `codex resume <id>` and the cleanup handles both.
- Not erased, documented as such: Claude Code's `plans/<slug>.md`, `paste-cache/`, `shell-snapshots/`
  and `sessions/<pid>.json` carry no session id; the copy on claude.ai stays with the user; anything
  the agent wrote to the repo, amem or a log despite the notice.
- Switching a session back to public keeps whatever is written from then on; the pending entry is
  dropped, so an earlier private phase is not erased either.
- Failover handoff of a private session opens a private session (the brief carries the transcript
  digest). A duplicate is a fresh public session.
- The sweep is a plain file removal by id, not a secure wipe; APFS snapshots and Time Machine keep
  what they already copied.
