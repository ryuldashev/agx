# 2026-09-03 — reopening a closed session actually brings the agent back

Branch: `worktree-restore-reopen-2026-09-03` (worktree `.claude/worktrees/restore-reopen-2026-09-03`).

## Why

Closing a session recorded a full snapshot in `recent-closed.json` — including the `restoreCommand`
Claude Code's SessionStart hook pins (`zsh -lc 'exec claude --resume <uuid> --fork-session'`) — but
reopening it rebuilt a bare shell: `restoreRecentClosed` called `session(from:)` without
`launchRestore`, and only that flag armed the transient pending slots the surface factory reads. The
pin sat in the persisted field, unread. Reopen was therefore a directory bookmark, never a session.

## What changed

1. **Reopen arms the restore pins.** `session(from:launchRestore:)` became
   `session(from:arming:)` over a three-case `SnapshotArming`: `.none` (a window reload, or a
   workspace shell rebuilt around a live session), `.launch` (pins AND the quit-time captures) and
   `.reopen` (pins only). A capture describes a clean quit that never happened for a session closed
   mid-run, and replaying one unasked is what `launchRestore` was written to prevent — so reopen takes
   the pins and leaves the captures. All three `restoreRecentClosed` paths pass `.reopen`, workspace
   reopen included, so every member of a reopened workspace comes back the same way.
   `undoPendingClose` (⌘Z, the 3-second grace window) still arms nothing and must not change: it hands
   back the SAME live `Session` object whose program never died.
2. **`restore list|open|last` over the control API + CLI.** `ControlRecentClosedNode` projects an
   entry (index, id, kind, title, workspace, cwd, ISO `closedAt`, `sessionID` or a workspace's
   `sessions` count, and the `restoreCommand` a reopen will run); `RecentClosedResolve` takes the
   printed index, the entry id/prefix, or the closed session's own id. `restore.open` echoes the
   reopened session's id — the id it had before the close, so `tree` is the read-back.
3. **Recently-closed section in the title-bar clock popover.** A labelled section under a divider
   rather than a segmented control: both groups are read in one glance and clicked in one press.
   The button now enables when there are closed items even with no other live session — the case that
   used to leave it dead in a one-session window. A11y ids `recent-closed-header`/`recent-closed-row`.
4. **`session new --workspace` accepts a workspace NAME.** Resolved only on a clean id miss, so a name
   can never shadow a workspace whose id starts with it; a real name collision errors with
   `ambiguous workspace name` (`ControlResolve.idsNamed` / `ambiguousNameMessage`).

Two things found while testing, both fixed here:

- **An out-of-range index no longer falls through to id-prefix matching.** `restore open 2` on a
  one-item list reopened entry 1 whenever that entry's id began with `2`. An all-digit target is now
  the index and nothing else. Caught by a test written for the projection, not by hand.
- **`isolated deinit` was aborting every hosted test that let one of four objects go** — a standing
  `make test-app` failure on master, from `1afe40a`, not from this branch. Back-deployed it lowers to
  `swift_task_deinitOnExecutorMainActorBackDeploy` and aborts in
  `TaskLocal::StopLookupScope::~StopLookupScope` with `pointer being freed was not allocated`
  (backtrace from the sentry envelope per `.claude/rules/ui-tests.md`). All four bodies only remove a
  notification observer or cancel a `DispatchWorkItem`, both thread-safe, so they never needed the
  executor: plain `deinit` plus `nonisolated(unsafe)` on the tokens it reads.
  Sites: `SystemWakeObserver`, `SystemAccessibilityObserver`, `AppActions`,
  `WorkspaceSidebar.Coordinator`. This is a latent app crash too, not only a test one — the sidebar
  coordinator deallocates in normal use.
- `ControlDispatcher.swift` crossed the 1000-line limit, so the five `Control*Options` value types
  moved to `ControlDispatcherOptions.swift`. Behaviour-preserving; no routing moved.

## Gates

- `cd agtermCore && swift test` — **2702 tests pass.**
- `make test-app` — **passes.** It did NOT pass on master; see the `isolated deinit` note above.
- `make lint` — **clean.**
- `agtermUITests/ControlRestoreReopenUITests` (9 tests) — **all pass** (31.8s, run 2026-09-03 08:48
  once the screen was unlocked). The earlier `Timed out while enabling automation mode` was a locked
  session, not a test fault:
  `xcodebuild test -project agterm.xcodeproj -scheme agterm -destination 'platform=macOS' \
   -derivedDataPath build/DerivedData -only-testing:agtermUITests/ControlRestoreReopenUITests`
- Manual, in an isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agxrr`, `restoreRunningCommand` on):
  created a session, pinned a restore command, closed it, and reopened it both by index and with
  `restore last` — **the pinned program ran and the session stayed up.** `session new --workspace lab`
  resolved the name. Both verified against the isolated socket only; the live terminal was never
  driven with a mutating command.

One thing worth knowing for the next person: a durable pane `exec`s the pinned line, so a pin that is
a one-shot command (`printf …`) reopens the session and then closes it the moment the command exits.
That is the durable contract, not a reopen bug — the real pin
(`zsh -lc 'exec claude --resume …'`) is long-lived. It also means the shell's `exec` binds to the
first command only: a pin like `touch x; exec zsh -l` runs `touch` and stops. Wrap multi-command pins
in `zsh -lc '…'`.

## Next

- The popover's row CLICK is verified by hand only: a synthesized XCUITest click on a SwiftUI `Button`
  inside an `NSPopover` does not fire the action (see `.claude/rules/ui-tests.md`). The test asserts
  the section and row are present and labelled.

## Code review pass (Opus, adversarial, over the whole day's diff)

A separate Opus subagent reviewed everything committed today. Findings applied here, in the second
commit:

- **A1 — `restore open` returned the wrong id.** The response reported `store.selectedSessionID`
  whatever the entry was, so a workspace entry whose members had all been taken restored an EMPTY
  workspace and still handed back the previously selected session's id. `reopenedSessionID(_:in:)`
  now answers from the snapshot for a session entry, and for a workspace entry only returns a
  selection confirmed to live in the rebuilt workspace.
- **A2 — a blank target silently meant "the newest".** `restore open ""` (an unset shell variable)
  reopened whatever was newest and ran its pin. The dispatcher now rejects a present-but-blank target
  with `restore.open target must not be blank`; an ABSENT target still means the newest, which is what
  `restore last` sends.
- **B1 (found by my own new test, fixed before the review) —** an out-of-range all-digit target fell
  through to UUID-prefix matching, so `restore open 2` could reopen entry 1 when entry 1's id started
  with a 2. An all-digit target is now the index and nothing else.
- **D1 — the popover could outgrow the screen.** Both lists are capped at `maxCandidates`, so the
  stack can reach twice the height one list ever did and a title-bar-anchored popover that tall gets
  repositioned or clipped. Wrapped in a `ScrollView` with `maxHeight: scaled(420)` and `.fixedSize`,
  so a short list keeps its natural height.
- **D2 — a dead row.** A `.session` entry with a nil payload drew a row whose click resolved to
  nothing, and the failed reopen did not consume the entry, so the row survived every attempt. Such
  entries are filtered out of the popover list.
- **E1–E4 — docs.** `reference.md` gained a full `## restore` section and `closed` in the
  response-shape bullet; `control-api.md` and `SKILL.md` got the same; `site/commands.html` now prints
  `restore last [--window W] [--json]` and `restore open … [--json]`, and distinguishes session rows
  from workspace rows in `restore list`; `site/docs.html` now says the reopen re-runs the pin only
  with **Restore running commands on restart** on, which is off by default.
- **E2 — five stale comments** in `Session.swift`, `AppStore.swift`, `AppStore+Restore.swift` and
  `agtermApp.swift` still described the pending slots as launch-only.

Gates re-run once after the fixes: `swift test` **2702 pass**, `make test-app` **255 pass**,
`make lint` **clean**.
