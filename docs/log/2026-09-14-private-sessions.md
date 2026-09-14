# 2026-09-14 — private sessions (`session.private`, no persistence, transcript cleanup)

Branch `worktree-private-sessions-2026-09-14` off `agent-failover-2026-09-11` (639180d, 14 ahead of
`origin/master`). ADR: `docs/decisions/0003-private-sessions.md`. Worktree
`.claude/worktrees/private-sessions-2026-09-14`.

## What
A session marked private leaves nothing on disk once it closes. The app owns this because the agent
inside cannot: Claude Code's classifier blocks any touch of its own transcripts. The app (a) never
persists a private session (no restore after relaunch, no durable abduco server), (b) tells the agent
it is private through the SessionStart context block, (c) after close deletes the agent's transcript,
history lines, todos and debug logs by exact session id, with a start-up sweeper for sessions closed
by a crash.

## Plan
1. Model: `Session.isPrivate`, `AppStore.setPrivate` (+ save), snapshot filter, no abduco.
2. UI: sidebar glyph, title marker, context-menu toggle, New Private Session menu + keymap token.
3. Control API: `session.private on|off`, `session.new --private`, `ControlSessionNode.private`,
   `agx spawn --private`, `agx context` (text + json), private line in the SessionStart context hook.
4. Cleanup: `PrivateSessionCleanup` (host-free path plan + history filter), pending-cleanup list in
   the state dir, sweeper on launch, result → log + notification.
5. Tests: cleanup planner, history filter, pending persistence, dispatcher/CLI for `session private`.
6. Docs: `site/docs.html`, ADR 0003, this log, skill reference, `site/commands.html`.

## Progress
- [x] 1 model — `Session.isPrivate` + `agentSessionTargets`, `AppStore.setPrivate`, `noteAgentSession` on every `session.restore`, snapshot/recency/selection/recent-closed filters, `DurablePane.shouldWrap(isPrivate:)`
- [x] 2 UI — sidebar `lock.fill` row icon, 🔒 in the OS title + lock in the title label, context-menu "Private Session" checkmark, Session ▸ New Private Session (⌘⇧P, `new_private_session`), Make Session Private/Public (`toggle_private`, keyless), palette rows
- [x] 3 control API + hook — `session.private on|off|toggle`, `session new --private`, `ControlSessionNode.private` (omitted when false), `(private)` tag in `agtermctl tree`, `agx spawn --private`, `agx context` `private` flag + PRIVATE_NOTICE line (reaches the agent through the SessionStart context hook), failover handoff inherits private
- [x] 4 cleanup + sweeper — `agtermCore/PrivateSession.swift` (`PrivateSessionCleanup`, `PrivateCleanupStore` → `<stateDir>/private-cleanup.json`), `agterm/PrivateSessionSweeper.swift` (2 s after discard, 3 s after launch, log + banner)
- [x] 5 tests — `PrivateSessionTests.swift` (target validation, restore-line parsing, history filter, sweep on temp home/tmp roots for claude + codex, pending store, snapshot/recent-closed filter, setPrivate sink, restore-pin capture, shouldWrap, tree read-back), dispatcher (`session.private` mode parse + `session.new --private`), CLI parse (`session private`, bad mode, `--private`), `formatTree` tag; pinned counts bumped (PaletteCommand 52, BuiltinAction 48)
- [x] 6 docs — `site/docs.html` "Private sessions" (restore section) + keymap tokens, `site/commands.html` `session.private` + `--private` + node field, skill SKILL/reference/examples, `.claude/rules/control-api.md`, `docs/ui-lexicon.md`, `FORK.md`, ADR `docs/decisions/0003-private-sessions.md`
- [x] gates: swift test (2748 green) / make test-app (250, 0 failures) / make lint (strict, clean; `AppActions.swift` sits at the 1000-line cap upstream — private actions live in `AppActions+Private.swift`, `PrivateCommand` in `SessionPrivateCommands.swift`, the dispatcher arm in `dispatchSessionPrivate`)
- [x] commit `145205b` on `worktree-private-sessions-2026-09-14` + `make deploy` → `/Applications/agx.app` (2026-09-15). **Deploy awaits relaunch**: the running instance still serves the old build; `agtermctl app relaunch` kills live sessions, so that step is Ruslan's. Branch not merged into master yet.

## Findings (running notes)
- `snapshot()` is called only from `save()`; filtering there covers `windows/<id>.json` and the legacy
  `workspaces.json`. `sessionSnapshot` also feeds `recent-closed.json` (three call sites → gated in
  `recordRecentClosedSession`); `workspaceSnapshot` (recent-closed workspace) filters too.
- The agent session id reaches the app only inside `restoreCommand` (`claude --resume <id> --fork-session`
  from `agx-session-restore.sh`; the INSTALLED `~/.config/agx/agent-status/` copy is newer than this
  branch's Resources and also pins `codex resume <id>`). Parsed on every `session.restore` into
  `Session.agentSessionTargets`, so a `/clear` mid-session keeps every id.
- On-disk per-session state Claude Code keeps here (2026-09-15): `projects/<cwd>/<sid>.jsonl` + `<sid>/`,
  `history.jsonl` (`sessionId`), `debug/<sid>.txt`, `file-history/<sid>/`, `session-env/<sid>/`,
  `tasks/<sid>/`, `/private/tmp/claude-<uid>/<cwd>/<sid>/`, `~/claude-archive/projects/<cwd>/<sid>.jsonl.gz`,
  plus agx's own `~/.claude/agx-usage/<AGX-ID>.json`. `todos/` does not exist here but is scanned.
  Codex: `~/.codex/sessions/yyyy/mm/dd/rollout-<ts>-<sid>.jsonl`, `history.jsonl` (`session_id`).
- Not cleaned (no id in the name): `~/.claude/plans/<slug>.md`, `paste-cache/`, `shell-snapshots/`,
  `sessions/<pid>.json` (claude removes it at exit). The action journal records ids only, no text.
- `DurableSpawn.reapOrphans` at launch already kills the server of any session not persisted — a private
  session's, if it had one — so the sweeper runs after it.
- `private` is a Swift keyword: fields are spelled `` `private` `` (`ControlArgs`, `ControlSessionNode`,
  `ControlSessionCreateOptions`), the model field is `isPrivate`.

## Not done / limits
- The copy on claude.ai (cloud sync of the session) is out of reach of the app — stays on the user.

## 2026-09-15 follow-up: id lost after relaunch

Ruslan relaunched, made `FEB43D13` private → no `private-cleanup.json`. `agentSessionTargets` were
filled only in `setRestoreCommand` (the hook's pin); a durable pane reattaches without re-running the
hook, so a restored session carried the pin in `restoreCommand` but no target. Fix: `session(from:)`
seeds targets from the persisted pin (`noteAgentSession`), test
`aRestoredSessionKeepsThePersistedPinAsAnAgentTarget`. The running (old) build cannot be fixed in
place; for the already-private session the workaround is to re-pin the same line through
`session restore`, which routes through `noteAgentSession` before the equality guard.

`PrivateCleanupStore.upsert` now MERGES targets (a close that learned no id keeps what an earlier pin
or launch recorded) and returns what it wrote; the sweeper runs that.

Live check pending (Ruslan closes it, we verify): agx session `FEB43D13-03CF-44E2-9397-2B820B54CD21`
("✳ Ранняя эякуляция и сексуальность", private, durable), Claude id
`805748e8-b320-4417-92ea-def52010ab9f`. Entry hand-written into `private-cleanup.json`; on disk before:
`~/.claude/projects/-Users-rus-me/805748e8….jsonl`, `~/.claude/session-env/805748e8…/`,
`/private/tmp/claude-501/-Users-rus-me/805748e8…/`, `~/.claude/agx-usage/FEB43D13….json`, 11 lines in
`~/.claude/history.jsonl`; no archive copy yet. The OLD running build would overwrite the entry with
empty targets on a tab close, so the close must be a relaunch: the new build sweeps it 3 s after launch.
