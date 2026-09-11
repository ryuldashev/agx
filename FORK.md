# agx — a fork of agterm

`agx` is a fork of [umputun/agterm](https://github.com/umputun/agterm) (MIT), branched at `c793b46`
on the v0.23.0 line. Upstream's architecture is the product: host-free `agtermCore`, a thin
SwiftUI/AppKit shell, and a control API that every feature is expected to be reachable through. This
fork keeps that contract and adds what a multi-agent day needs on top of it.

It is a fork, not a patch set: there is no plan to send this upstream and no obligation to track it
commit for commit. What follows is what diverges and how to bring a newer upstream in when it is
worth it.

## What it adds

**Connected agents** (`Settings ▸ Agents`) — a named list of local agent CLIs, each just a display
name and a shell line, so anything runnable qualifies. A "Found on This Mac" section probes `PATH`
for the CLIs it knows (Claude Code, Codex, Gemini, Copilot, Cursor, OpenCode, Crush, Aider, Amp,
Goose, Kimi, Qwen, Droid, Mimo, Hermes, Pi) and offers one-click Connect. The probe adds `~/.local/bin`,
`~/.bun/bin` and the Homebrew prefixes itself: the GUI is launched by launchd, whose `PATH` has none
of the directories agents actually install into.

**Agent profiles** (`agtermCore/AgentCatalog.swift`, ADR-0003) — everything agx knows about one CLI
lives in its `AgentProfile`: how it takes a brief (`claude "$b"` vs `gemini -i "$b"` vs `opencode
--prompt "$b"`), its resume line (`{id}`), which hook file its status hooks merge into and in which
dialect, how `agx context` reaches it, and its config directory. The installer, `ScheduledLaunch` (schedule
+ failover), the restore pin and `agx spawn` read the profile; nothing else names an agent. A profile
with only a name and binary is launch-only: seeded positionally, no glyph, no resume — the graceful floor.
Depth today: Claude Code and Gemini CLI (hooks + resume + context), Codex (hooks + resume + context via
its adapter), Cursor (hooks without a permission event + resume + context), OpenCode (plugin status,
`--prompt` seed, `--session` resume), Mimo (seed + resume only). Measured facts per CLI —
`docs/reference/agents/<binary>.md`. `scripts/agx` mirrors the seed/context/trust part of the catalog in
its `AGENTS` table (python can't read the Swift catalog); keep the two in step.

**⌥ names the chrome** — holding ⌥ alone drops a panel under the title bar listing every visible chrome
control as icon + the short token used to talk about it + its shortcut, so a button can be reported by name
instead of by screenshot. The tokens and the vocabulary they belong to live in `docs/ui-lexicon.md`.
`AGX_HINTS_ALWAYS=1` pins the panel open, since a held ⌥ cannot be screenshotted.

**"Hide split" hides the split** — upstream's title-bar/⌘D hide follows `splitFocused`, and a fresh split
focuses the new pane, so the second press maximized the shell just opened and buried the pane being worked
in. Here the button always leaves the primary pane on screen. Focus-following zoom is untouched elsewhere:
⌃1/⌃2 still swap which pane a hidden split shows, and `session.split --hide` keeps upstream's semantics.

**Pane zoom instead of the scratch button** — the title bar's scratch toggle became a pane-zoom button
(⌘⇧⏎). A session already carries four terminal surfaces (main, split, scratch, quick terminal) and the split
covers what the scratch was for, while zoom had no button at all. The scratch itself is untouched: ⌘J, the
palette and `session.scratch` still reach it.

**Scheduled sessions** (`agtermctl schedule add --at "tomorrow 09:00" --brief "…"`) — the app itself opens
a session at a future time and launches the agent with the brief as its first message. Jobs persist in
`<stateDir>/scheduled.json`, fire from a main-runloop timer, on the next launch when the app was closed at
the time, and on display wake; one overdue by more than 24h is parked as `missed` for `schedule run` or
`cancel` instead of firing days late. Control-native like `session.hud`: `schedule.add/list/cancel/run`,
top-level `tree.scheduled`, and `schedule.*` events, with no menu twin. `agx schedule …` wraps it for
in-pane agents. Replaces the launchd-plist-plus-shell-script pattern, which needed the Mac awake and the
app already running at the moment the job fired.

**Its own theme** — `Resources/custom-themes/agx` is the fork's default theme
(`AppSettings.defaultTheme`). It currently carries upstream's neutral palette verbatim: a warm-dark
variant read as worse, not different, and the windows are told apart by the icon and the background
image instead. Keeping the separate FILE means retuning it never touches upstream's.

**Durable agent panes** — a command session's program runs as a client of a detached abduco session
server named by the session id (`vendor/abduco`, ISC, bundled at `Resources/abduco/abduco`), so quitting,
relaunching or crashing agx reattaches the SAME process: an agent keeps its context, prompt cache and
unfinished turn instead of coming back as a `claude --resume … --fork-session` re-run. On by default
(Settings ▸ General ▸ Durable agent panes; `session new --durable` forces one session). Closing a session
kills its server; a program that exited while agx was away is replaced on the next launch by the restore
command. Design, lifecycle and the one vendored patch: `docs/decisions/0001-abduco-durable-panes.md`.

**The `agx` CLI and its SessionStart hooks, shipped in the app** — `scripts/agx` (python3) is the
agent-facing side of the control API: `agx context` describes the UI an in-pane agent lives in, `agx spawn`
opens a peer session seeded with a brief, `agx schedule` wraps scheduled sessions, `agx run` runs a command in
the pane's overlay. It is bundled at `Contents/Resources/agx`, finds `agtermctl` as its `../MacOS` sibling,
and Help ▸ Install Command Line Tool links it into `/usr/local/bin` beside `agtermctl` (one admin prompt for
both). Help ▸ Install Agent Status Hooks adds two `SessionStart` hooks per hook-capable profile from
`Resources/agent-status/` with the same marker-guarded merge as the status hooks: `agx-session-restore.sh
--resume-line '<profile template>'` pins the agent's resume line for the session id on stdin as the pane's
restore command, `agx-session-context.sh --format claude|codex|cursor` injects `agx context` as additional
context in that agent's envelope. Codex's adapter calls both from its `session-start` action. All are gated
on `AGTERM_ENABLED=1`, use python3 rather than jq, print nothing on failure and always exit 0, so outside agx
they cost one `test` and can never block a turn. The installer bakes the bundled `agtermctl`/`agx` paths into
the wrappers, so nothing needs to be on PATH.

**Agent failover** — when Claude Code stops on an API error, the app decides what happens next instead of
leaving the pane at "You're out of usage credits. Run /usage-credits … or /model". Claude Code's
`StopFailure` hook (`Resources/agent-status/agx-agent-failure.sh`, installed by Help ▸ Install Agent Status
Hooks — the plain `Stop` hook does NOT fire on an API-error turn) reports the error type and message over
`agtermctl session failure`. A model's spent pool ("out of usage credits … keep using X") types `/model <next>`
from the Settings ▸ Agents ▸ Failover ladder (default `opus[1m]`, `sonnet[1m]`; X's family is marked exhausted
for that session) and a continue prompt; a weekly/session account limit, an auth or billing error, a spent
ladder, or a main-pane exit while the agent was mid-turn hands the task to another connected agent (default:
the first of another kind, e.g. Codex) in a new `<name> → <agent>` session seeded with a brief built from the
Claude transcript (last three prompts, last answer, transcript path); `overloaded`/`server_error` re-prompt
after 20s up to three times. Every action posts a notification and a `failover` event, and reads back as the
session node's `failover`. Host-free policy and transcript digest: `agtermCore/AgentFailover.swift`; the
typing/spawning side: `agterm/AgentFailoverCoordinator.swift`. `docs/decisions/0002-agent-failover.md`.

**Workspace defaults** — a workspace pins the directory new sessions open in and the connected agent
they run, so opening a tab in `mmee` lands in `~/mmee` with Claude Code already running. Set from the
sidebar's right-click ▸ Workspace Defaults… or over the control API:

```
agtermctl workspace defaults --dir ~/mmee --agent "Claude Code" --target work
agtermctl workspace defaults --background ~/Pictures/mars.png --background-opacity 0.25 --target work
agtermctl workspace defaults --target work      # read it back
agtermctl workspace defaults --dir '' --target work   # clear just the directory
```

A workspace also pins its **background image** (`--background`, `--background-opacity`,
`--background-fit`, or the sheet's Background row): every session created there starts with it, so a
window says which project it belongs to before you read a word of it. The spec is seeded onto the
session at CREATION and then owned by the session — restyling one session with `session.background`
never edits the workspace, and editing the workspace never restyles the sessions already open.

Precedence at create time is: an explicit `--cwd`/`--command` (or a folder dropped on the workspace),
then the workspace default, then the global new-session directory. A pin therefore never overrides a
caller that asked for something specific, and an agent deleted from Settings degrades to a plain
shell rather than failing the create.

## Identity — why both can run at once

The fork is meant to be installed BESIDE upstream agterm, not instead of it, so nothing about it
resolves to an upstream path. All of it is derived from `agtermCore/Sources/agtermCore/Brand.swift`;
renaming the product is a change to that file and the build settings that carry the same strings.

| | upstream | this fork |
|---|---|---|
| bundle id | `com.umputun.agterm` | `uz.marshub.agx` |
| app / binary | `agterm.app` | `agx.app` |
| state dir | `~/Library/Application Support/agterm` | `~/Library/Application Support/agx` |
| config dir | `~/.config/agterm` | `~/.config/agx` |
| control socket | `<state>/agterm.sock` | `<state>/agx.sock` |
| log subsystem | `com.umputun.agterm` | `uz.marshub.agx` |
| Swift module | `agterm` | `agterm` (`PRODUCT_MODULE_NAME`) |
| About panel | agterm.com, © Umputun | github.com/ryuldashev/agx, © Ruslan Yuldashev, credit line "A fork of agterm by Umputun, MIT" |
| Help menu | Developer Documentation → agterm.com | "agx on GitHub…" + upstream docs, labelled as agterm's |

Two things deliberately keep upstream's names:

- **`AGTERM_*` env vars and `TERM_PROGRAM=agterm`.** Every agent hook, cookbook recipe and shell
  integration written for agterm keys off those names. A session addresses THIS app because
  `AGTERM_SOCKET` points at this app's socket, not because the variable is spelled differently.
- **`agtermctl`.** The CLI name is what the installed agent skill, the hooks and every recipe call.

`PRODUCT_MODULE_NAME: agterm` is deliberate too: `PRODUCT_NAME: agx` would otherwise rename the Swift
module and break `@testable import agterm` in every upstream test file, for no gain.

On first run, when the fork has no config directory of its own, `~/.config/agterm/*.conf` is copied
across — a fork of a tool you already use should start with the keymap you already wrote. Loose
`.conf` files only (hooks bake in the other app's `agtermctl` path), only when the destination does
not exist, and never when the config directory was chosen explicitly or `AGTERM_STATE_DIR` is set —
seeding an isolated directory would defeat exactly the isolation it was asked for.

## Behaviour changes to upstream code

- **`agtermctl` reads `AGTERM_SOCKET` first**, before `AGTERM_STATE_DIR` and the default rendezvous
  path (upstream ignores the variable). With two builds installed, `PATH` decides which `agtermctl`
  binary runs but no longer which app it talks to: a command inside a pane addresses the app that
  spawned it. It also means an instance refused the socket lock advertises `<socket>.unavailable` and
  its shells fail loudly instead of quietly driving the owner's terminal.
- **`session new` and the GUI's "+" resolve through the workspace seed** rather than the global
  new-session directory alone. With nothing pinned the behaviour is byte-identical to upstream.
- **`tree` workspace nodes carry `defaults`**, omitted when the workspace pins nothing — an untouched
  workspace serializes exactly as it did before the field existed, so upgrading does not rewrite
  `workspaces.json`.

## Where the divergence lives

New files (no upstream conflict surface):

```
agtermCore/Sources/agtermCore/Brand.swift              fork identity, one place
agtermCore/Sources/agtermCore/AgentCatalog.swift       known agents + PATH probe
agtermCore/Sources/agtermCore/WorkspaceDefaults.swift  the seed and its precedence rules
agtermCore/Sources/agtermCore/AppStore+Defaults.swift  store read/write + shared resolver
agtermCore/Sources/agtermCore/AppStore+ControlTree.swift  extracted from AppStore.swift (line budget)
agterm/Views/AgentsSettingsView.swift                  Settings ▸ Agents
agterm/Views/WorkspaceDefaultsSheet.swift              the sidebar sheet
agtermCore/Tests/…/WorkspaceDefaultsTests.swift, AgentCatalogTests.swift
```

Touched upstream files, in rebase-risk order: `AppStore.swift`, `ControlServer.swift`,
`ControlProtocol.swift`, `ControlDispatcher.swift`, `AppActions.swift`,
`WorkspaceSidebar+ContextMenu.swift`, `SettingsModel.swift`, `SettingsView.swift`, `Snapshot.swift`,
`Workspace.swift`, `ConfigPaths.swift`, `project.yml`, `scripts/*`, plus the mechanical
`agterm`→`agx` path rename through `docs/`, `plugins/` and `cookbook/`.

## Rebasing on a newer upstream

Upstream ships roughly a release every three days, so this is a deliberate, occasional operation, not
a routine one. Only rebase for something you actually want.

```bash
git remote add upstream https://github.com/umputun/agterm     # once
git fetch upstream
git log --oneline HEAD..upstream/master        # decide whether it is worth it
git checkout -b rebase-YYYY-MM-DD
git rebase upstream/master
```

Expect conflicts in the four control-API files (upstream adds commands to the same switches) and in
`project.yml`. The path rename conflicts are mechanical — take upstream's text, then re-run:

```bash
grep -rn "com\.umputun\.agterm\|config/agterm\|Application Support/agterm\|agterm\.sock" \
  CLAUDE.md ARCHITECTURE.md docs/troubleshooting.md plugins cookbook
```

Then, in order: `./scripts/test.sh` (core), `swiftlint --strict`, `make build`, `./scripts/test-app.sh`.

## Verify

```bash
./scripts/test.sh        # agtermCore + agtermctlKit — 2595 tests
swiftlint --strict       # the 1000-line file budget is real; split on the 2nd reason to change
make build               # xcodegen + xcodebuild, must be warning-free
./scripts/test-app.sh    # hosted AppKit tests
```

**Known baseline failure.** On macOS 26.3 with the pinned ghostty rev (`0ba6250`), seven hosted tests
kill the host process with `malloc: pointer being freed was not allocated` — `FullScreenChordTests`
(leader case), `SidebarExpansionMirrorTests` ×2, `SystemWakeObserverTests` ×2,
`UndoCloseShortcutTests` ×2. **Verified identical on a pristine upstream checkout of the same commit**
(2026-08-18), so it is an upstream/toolchain fault, not fork damage. Re-check against a clean worktree
before spending time on it, and treat any EIGHTH failure as ours.
