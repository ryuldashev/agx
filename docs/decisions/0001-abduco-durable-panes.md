# 0001 — Durable agent panes on abduco (soft restart)

Status: accepted 2026-09-02 (go from Ruslan; default ON, vendor patch kept).

## Context

The pane's pty is created by libghostty inside the app process. Quitting agx closes every pty, so
every session's program gets SIGHUP and dies. Today's recovery is a Claude Code `SessionStart` hook
(`~/.claude/settings.json`) that pins `session.restore` to
`zsh -lc 'exec claude --resume <id> --fork-session'`. On the next launch that line is typed into a
fresh login shell (`CommandRestore.restorePlan`: a restore override wins, exec path unused). The cost:

- an unfinished turn is lost (the process died mid-tool-call);
- the resumed process re-reads the whole conversation: prompt-cache MISS at full price;
- `--fork-session` mints a new Claude session id, so the session cost counter and the
  `agx usage` emit key restart from zero.

`vendor/abduco` (ISC, v0.6, commit `c5b0f0f`) is already vendored and verified standalone: its
session server reparents to launchd, survives the spawner, and a later attach from an unrelated
process lands in the original program. It is not wired into Swift yet (0 references).

Live snapshot facts that shape the design (`~/Library/Application Support/agx/windows/*.json`):
every agent session carries `initialCommand: "claude"` (or a `zsh -lc 'exec claude "<brief>"'`
spawn line) plus the hook-pinned `restoreCommand`. Both are shell lines run by libghostty's
`command` through `sh -c`, so a wrapper is a string prefix, not a new spawn path.

## Decision

**A `--command` session runs its program as a client of a detached abduco server named by the
session id. App quit detaches; session close kills.** Plain login-shell sessions are not wrapped.

1. **Wrapper line** (host-free, `agtermCore/DurablePane`, pure string composition, unit-tested):

   ```
   '<Resources>/abduco/abduco' -A -f '<sock>' /bin/zsh -lc 'printf %d $$ >'"'"'<sock>.pid'"'"'; exec <line>'
   ```

   - `-A`: attach if the server is alive, else create. `-f`: a server whose program already exited
     while detached prints its exit status and is *replaced* — without `-f` the client would exit
     with that status and the pane would close, dropping the session from the sidebar.
   - `<line>` is what `restorePlan` produced: `plan.command` (fresh: `claude`, a spawn brief, an
     `ssh …`) or the restore override with its newline stripped (`zsh -lc 'exec claude --resume …'`).
     The override is the fallback the server runs only when there is nothing alive to attach to —
     today's behaviour becomes the fallback, not the default.
   - `$$` in the zsh wrapper is the program's pid after `exec` (the `zsh -lc` restore line execs
     again; the pid survives every exec). `<sock>.pid` is written by the program's own shell before
     exec, so agx never has to guess which process is the program.
   - The pane's own process tree stays `login → sh → abduco(client)`; the program lives under the
     server: `abduco(server, reparented to launchd) → claude`.

2. **Name = absolute socket path** `<stateDir>/abduco/<session-uuid>` (abduco takes a name starting
   with `/` verbatim). Default: `~/Library/Application Support/agx/abduco/<uuid>` = 82 bytes,
   under the 104-byte `sun_path` cap; an `AGTERM_STATE_DIR`-isolated Debug instance gets its own
   dir and **cannot attach the live app's servers**. A state dir that pushes the path past 100
   bytes disables wrapping for that instance (logged), never a dead pane.

3. **Lifecycle — two paths, kept distinct.**
   - *App quit / window close / crash*: surfaces are torn down as today; the client dies with its
     pty, the server keeps running. Nothing to add: this is abduco's contract, and it also holds
     when the app crashes (no teardown runs).
   - *Session closed for good* — `AppStore` hard close (`closeSession`, grace-close finalize,
     workspace delete): the store calls a new `onSessionDiscard(session)` hook; the app side reads
     `<sock>.pid`, SIGTERMs the pid's **parent** (the server: its handler `exit()`s, the atexit
     unlinks the socket, the closing pty master SIGHUPs the program), then removes the pid file.
     Pid read via `sysctl KERN_PROC_PID` → `e_ppid`, same family of calls `ForegroundProcess`
     already owns. A missing/stale pid file is a no-op.
   - A program that exits on its own: server exits after handing the status to the client, client
     exits, pane closes, session closes; the discard hook finds nothing to kill.

4. **Read-back stays truthful.** `tree`'s `foreground` for a durable pane is read from the pid
   file (the program's argv, `claude --resume …`), not from the pane's foreground group (`login`,
   unreadable, then the abduco client). So the sidebar label, `agx context`'s `running claude`,
   and the cookbook conversation picker keep seeing `claude`. `ControlSessionNode` gains
   `durable: Bool?` (nil when not wrapped).

5. **Opt-in, then default.** `AppSettings.durablePanes: Bool?` (Settings ▸ General: "Durable
   agent panes — survive app restart"), default off until the first soft restart is verified on
   Ruslan's real sessions, then flipped on. `session.new --durable` forces it for one session
   (dispatcher validates: meaningless without `--command`, like `--wait`). No new command, so the
   synchronized command count does not move; `commands.html`, the skill reference and
   `site/docs.html` document the flag and the setting.

6. **Bundling.** `scripts/setup.sh` builds `vendor/abduco` (`-D_DARWIN_C_SOURCE`, as in the
   vendoring commit) and stages the binary to `agterm/Resources/abduco/abduco`, a gitignored build
   artifact like `Resources/ghostty`, copied as a folder reference (exec bit kept, same as `hud`).
   The app resolves `Bundle.main.resourceURL/abduco/abduco`; if absent, spawn is unwrapped and a
   log line says why.

7. **Migration.** The first restart on the new build still forks: the running programs are not
   under a server yet. Every restored agent pane comes back wrapped, and the restart after that is
   soft. No snapshot format change: durability is decided at spawn from the setting/flag; the
   server's existence is the persisted state (the socket file), and `<sock>.pid` is the only
   sidecar.

## Rejected alternatives

- **Probing liveness in Swift and choosing attach vs create.** `abduco -A -f` already makes
  exactly that decision atomically; a Swift probe would race it and add a second source of truth.
- **`ABDUCO_SOCKET_DIR` / `~/.abduco/<name>`.** Shares a namespace with the user's own abduco use
  and with every agx instance; an absolute path per state dir isolates for free.
- **Wrapping plain shells too.** Nothing to preserve, and it would turn every shell's foreground
  capture into `abduco`.
- **Finding the server by scanning all pids for the socket path in argv.** Works, but a per-close
  sysctl sweep for what a 5-byte pid file answers; the pid file also gives the truthful `foreground`.
- **Patching abduco to write the pid file / handle a kill verb.** The zsh wrapper does it outside
  the binary. The vendor tree carries exactly ONE patch, forced by the proof: 0.6's `-A -f` on a
  session whose program died while detached races the old server's socket unlink and fails
  `create-session: Address already in use`. `session_wait_gone()` in `abduco.c` waits (bounded,
  2 s) for the server to go before creating; once it has, `session_connect()` clears the stale
  file itself. Without it every fallback after a detached exit would land on a dead pane.
- **tmux/dtach.** See `c5b0f0f`: a second window manager, and GPLv2 respectively.

## Consequences

- A live Claude session keeps its process, context, cache and session id across `agx` restarts,
  crashes, and window close/reopen. An unfinished turn continues; the redraw is a SIGWINCH.
- Whether that happened is read back, not inferred: `tree.attached` and a `session.durable` event
  carry attach-vs-create per spawn (decided by the pid file's program being alive under this socket's
  server). A `--resume` fallback also restores the conversation, so a context check cannot tell the two
  apart — the first restart after the deploy proved it (2026-09-02: every session forked, as migration
  predicts).
- abduco keeps no screen, so a reattached program repaints only what it believes changed and drops a
  SIGWINCH that reports its old size: the spawn forces a real resize (`DurableSpawn.nudgeRedraw`, one
  column narrower then back, 0.8 s and 2.5 s after spawn). The OSC title is in the same position — held
  by the program, re-emitted only on its next change — so the snapshot carries `title` and a
  session whose abduco server is still alive adopts it at RESTORE (`WindowLibrary.adoptDurableTitles`
  → `Session.adoptPendingTitle`), before the pane realizes, so a durable session in an unopened
  workspace shows its title and not its cwd. Every other restored session drops the saved title.
  `SessionSnapshot` has a custom `init(from:)`; the `title` key must be decoded there, not only added
  to `CodingKeys` (the in-memory round-trip test misses that path — `WindowLibraryTests` covers disk).
- Launch sweeps `<stateDir>/abduco/` against every indexed window's persisted sessions and kills the
  rest (`DurableSpawn.reapOrphans`), so a window file removed by hand or a crash between discard and
  pid-file removal cannot leak a server.
- `^\` (abduco's default detach key) in a durable pane detaches the client, which closes the pane
  and — because that is a session close — kills the program. Same outcome as SIGQUIT today; noted
  in docs. Not remapped: any other byte is something a program might legitimately receive.
- The program's environment is frozen at first spawn. `AGTERM_SOCKET`, `AGTERM_SESSION_ID`,
  `AGTERM_WINDOW_ID`, `AGTERM_WORKSPACE_ID` are stable across restore; `AGTERM_PANE_ID` is minted
  per surface, so after a reattach the program's token names a surface that no longer exists —
  `Session.paneRole(forToken:)` returns nil for it and the status hook falls back to its baked
  `--pane left`, which is the main pane. Only main panes are durable, so nothing misroutes.
- `ssh …` command sessions become durable as well: a detached remote shell survives a restart.
- A macOS reboot kills the servers; `-f` then runs the fallback line, i.e. exactly today's resume.
- Servers are per state dir. Removing a state dir by hand orphans its servers; `abduco`'s own
  listing does not show absolute-path sessions, so `docs/troubleshooting.md` gets a
  `pkill -f '<stateDir>/abduco/'` line.
- `restoreRunningCommand` off + durable on: a restored `initialCommand` is still gated by the
  toggle, so the pane comes back a plain shell and the server stays alive, orphaned until the
  session is closed. The setting UI states the dependency; `session.new --durable` without the
  restore toggle is accepted with a note in the response.

- While detached the server keeps draining the program's pty (`read_pty` stays true once a client
  has connected), so the program never blocks on output and a turn keeps running; what it printed
  meanwhile is dropped, not replayed. Claude Code's TUI repaints on the attach-time SIGWINCH, so
  the screen is current; a plain shell would show only its next prompt.
- Build: `make -C vendor/abduco CPPFLAGS=-D_DARWIN_C_SOURCE` (the Makefile's strict POSIX
  defines hide `SIGWINCH`/`VLNEXT` on macOS).

## Verification

1. **Standalone, done 2026-09-02** — `scripts/durable-proto.py` (13 checks, all pass): the wrapper
   line under a pty; pid file names the program; server reparented to launchd; client's pty closed
   (an app quit) → program + server survive; reattach from a new pty → the SAME program pid
   answers; SIGTERM to the pid file's parent → server, program and socket gone; program killed
   while detached → `-A -f` reports the old exit and creates a fresh program in the same pane.
2. Next: `swift test` for `DurablePane` composition/quoting, `restorePlan` unchanged, dispatcher
   `--durable` validation, node round-trip; `make test-app`; `make lint`.
3. Isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agx-d1`, own socket): create a durable
   `claude` session, SIGTERM the instance, relaunch, `tree` shows the same `foreground` pid.
4. Full live restart of the deployed app only with an explicit go: it still kills today's ~12
   non-wrapped sessions once.
