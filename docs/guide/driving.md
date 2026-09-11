# Driving AGX from an agent

An agent in an AGX pane is not sandboxed in a terminal: it is operating the user's UI. It can read
which sessions are open and who needs attention, open a peer with a task, run a command in its own
side pane, show a document, and schedule work for later — over the same control socket the user's
shortcuts go through. `agx` is the agent-facing wrapper over `agtermctl`.

## Quickstart: the first five commands in a new session

**1. Who am I, what is on screen.** Injected into a Claude/Codex/Gemini pane's first turn by the
`SessionStart` hook; call it again whenever the picture may have changed.

```
$ agx context
me: "◐ AGX user guide v2" [2A6E0D69] · workspace agx · pane left · cwd /Users/rus/agterm · running claude · blinking
AGX v0.24.0  ·  socket ok

what the user sees now:
  window "window 1" [512145C0] frontmost, fullscreen, zoomed
  app focus: workspace agx → "✳ Dashboard-listview доступность в ридере"
  sidebar: tree, visible  ·  quick terminal: hidden  ·  workspace filter: off

open sessions (15 across 11 workspaces):
  mars: ✳ Payroll интеграция(claude)[reattached] · ✓ ✳ Mars онлайн-курсы(claude)[2 unseen,reattached] · …
  agx: ● ◑ Keyboard Shortcuts(claude)[blinking] · ✳ AGX user guide(claude)[split] · ● ◐ AGX user guide v2(claude)[blinking]

you can drive this UI (agtermctl — the app's control socket, already reachable here):
  …                                       # the manifest below, then "you cannot"
```

The first line is the only reliable answer to *which session is mine*. Note `app focus` — the
session the user is looking at is a different one.

**2. Run a shell step here, not in the chat.** A finite command runs in an overlay on your own pane;
you get the output and exit code, the user watches it happen.

```
$ agx run "git log --oneline -1"
4141139 Add the AGX user guide: docs/guide, Help ▸ agx Guide in the reader pane
[agx run: exit 0]
```

`--pane split` runs it over the split pane instead. The overlay closes when the command exits;
for something that must stay alive — a tunnel, a dev server — use the scratch:
`agtermctl session scratch on --command "<cmd>"`, then `agtermctl session text --pane scratch`.

**3. Show a document instead of pasting it.** Write the plan or report, open it once, keep editing.

```
$ agx reader docs/plans/guide.md          # this session's right pane, re-renders on save
$ agx reader close
```

**4. Delegate a separable task to a visible peer.**

```
$ agx spawn --brief "Audit docs/ for stale paths; write docs/audit.md as you go" --name "Docs audit" --json
{"id": "2F5D2E0F-2A63-4CCE-8E4B-AD1C2E3B8F80", "seeded": true, "foreground": false, "cwd_trusted": true}
```

The peer starts with the brief as its first message, in your workspace and directory. It cannot ask
you anything, so the brief is a complete task. Prefer this over an in-turn subagent when the user
should *see* and steer the work; the Agent tool is invisible in the sidebar and returns to you.

**5. Tell the user, and mark yourself.**

```
$ agtermctl notify "Guide draft ready — open in the reader" --title "AGX guide"
$ agtermctl session status completed        # the hooks do this for Claude/Codex/Gemini; others do it by hand
```

## `active` is almost never your own session

`--target` accepts a session id, a unique prefix, or `active`, and **`active` means the session the
user has selected in the frontmost window** — the one they are looking at — which is some other
pane whenever they are watching another agent. Every mutating command on `active` (`type`, `close`,
`scratch`, `overlay`, `reader`, `status`) lands there. Address yourself by the id `agx context`
prints on its first line, or by `$AGTERM_SESSION_ID`:

```sh
agtermctl session status active --target "$AGTERM_SESSION_ID"
agtermctl session close  --target "$AGTERM_SESSION_ID"        # "close the session" means this one
```

`agx run`, `agx reader`, and `agx spawn` already default to the caller; bare `agtermctl session …`
does not.

## What a pane knows on start

| variable | value |
|---|---|
| `AGTERM_ENABLED` | `1` — the hooks act only when it is set |
| `AGTERM_SOCKET` | this app's control socket; a pane addresses the instance that spawned it even with two builds installed |
| `AGTERM_SESSION_ID`, `AGTERM_WORKSPACE_ID`, `AGTERM_WINDOW_ID` | ids for `--target` |
| `AGTERM_PANE` / `AGTERM_PANE_ID` | `left` / `right` and the surface id |
| `TERM_PROGRAM` | `agterm` |

## The `agx` verbs

| verb | does | chapter |
|---|---|---|
| `agx context [--json]` | the board as text, plus the manifest of what you can drive and cannot | above |
| `agx run "<cmd>" [--pane split]` | finite command in an overlay on your pane, output + exit code | above |
| `agx reader <file.md> [--target ID]` · `agx reader close` | live-reloading document in the split pane | [Reader](reader.md) |
| `agx spawn --brief "…" [--name T] [--workspace-name W] [--cwd P] [--agent A] [--foreground] [--json]` | peer session seeded with the brief | [Agents › Spawning](agents.md#spawning-with-a-brief) |
| `agx schedule add --at <t> --brief "…"` · `list` · `run <id>` · `cancel <id>` | the app opens a seeded session at that time | [Agents › Scheduled](agents.md#scheduled-sessions) |
| `agx usage [--json]` | per-session model, context, cost, and the account pools | [Agents › Usage](agents.md#usage) |

## `agtermctl` essentials

The full verb set is agterm's ([agterm.com/commands](https://agterm.com/commands), Help ▸ agterm
Control API Reference…); these are the ones a day with agents uses:

```sh
agtermctl tree --json                                   # the whole model; read-back for everything
agtermctl session text --target <id|prefix> [--lines N] # read another session's terminal
agtermctl session type --target <id> --select "text\n"  # type into it (\n submits)
agtermctl session select --target <id>                  # bring it to front
agtermctl session status active|completed|blocked|idle [--blink] --target <id>
agtermctl session hud open "<message>" --target <id> [--detail …] [--spinner]   # passive panel
agtermctl session overlay open "<cmd>" --target <id> [--size-percent 60]         # a program over a session
agtermctl session failure rate_limit --handoff --target <id>   # hand my task to another agent now
agtermctl restore list | open <n> | last                # recently closed; reopen resumes the agent
agtermctl workspace new "<NAME>"                        # positional, not a flag
agtermctl notify "<body>" [--title "…"]                 # desktop notification tied to a session
printf '%s\n' a b | agtermctl pick --prompt "Which?"     # native picker, blocks until chosen
agtermctl events                                        # stream status/session/schedule/failover events
```

`session type` returns when the keys are queued, so a `session text` right after it races the
program. Positional where the CLI says so: `session move <workspace>`, `workspace new "<NAME>"`,
`notify "<body>"`, `session overlay open "<cmd>"`.

## Hooks and the skill

The three Help ▸ Install… items are described file by file in [First run](first-run.md). What
they mean for an agent:

- The **status hooks** report `active` / `completed` / `blocked` per turn, inject `agx context` on
  `SessionStart`, pin the resume line a relaunch will run, and report `StopFailure` for failover.
  Each is a no-op outside AGX and always exits 0, so it can never block a turn.
- The **agterm skill** (`~/.claude/skills/agterm/`) is the control model and every command, so an
  agent can build its own layout without being told the API.
- The **CLI symlinks** matter only outside a pane; inside, the hooks bake the bundle paths in.

## The action journal

`~/Library/Application Support/agx/journal.jsonl` records every ⌘/⌃ chord the app saw, every
built-in action with its origin (keymap or palette), every mutating control request (command,
target, caller), and the scratch / split / close state flips. Plain typing is never recorded.
When the UI did something nobody remembers asking for — a scratch over an agent, a split hiding
the wrong pane — the journal answers "what drove it":

```sh
tail -f ~/Library/Application\ Support/agx/journal.jsonl
```

## What an agent cannot do

- **Message another agent structurally.** `session type` is fire-and-forget stdin; there is no
  request/reply. To get an answer, poll `session text` on it.
- **See pixels.** No window screenshot. An agent reads terminal buffers and `tree`, not the chrome —
  which is what the ⌥ hint panel and the [UI lexicon](../ui-lexicon.md) tokens are for when the
  user reports a button.
- **Edit settings on disk.** `settings.json` is held in memory and rewritten at quit, silently
  reverting the edit. Change UI state through `agtermctl` or the Settings window.
- **Spawn a bare binary.** `session new --command` execs that argv under the GUI's minimal `PATH`; a
  binary not on it exits 127. Workspace defaults and `agx spawn` resolve the agent for you; a
  hand-written command should be a full path or a `zsh -lc '…'` line.
