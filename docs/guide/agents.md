# Agents

An agent in AGX is a program in a session that AGX knows a little about: how to hand it a first
message, how to resume it after a relaunch, which hooks make it report status, and what to do when
it stops on an error. All of it is optional — an unknown CLI still runs in a pane — but with it,
thirty agents in the sidebar read like a to-do list instead of thirty terminals.

## Connected agents

Settings ▸ Agents. **Found on This Mac** probes `PATH` plus `~/.local/bin`, `~/.bun/bin`, and the
Homebrew prefixes for the CLIs AGX has a profile for; **Add Custom Agent…** takes any name and shell
line. What AGX knows per agent is one manifest, `agents/<binary>/agent.json` in the app's
`agent-status` resources:

| agent | status glyphs | resume after relaunch | `agx context` on start |
|---|---|---|---|
| Claude Code, Codex, Gemini | hooks | ✓ | hook |
| OpenCode, Pi | plugin | OpenCode | line in front of the brief |
| Cursor, Mimo | – | ✓ | line in front of the brief |
| Hermes, Aider, Amp, Goose, Kimi, Qwen, Droid, Crush, Copilot | – | – | line in front of the brief |

An agent with only a name and binary is launch-only: it runs, it reports nothing.

## Workspace defaults

Right-click a workspace row ▸ Workspace Defaults…, or:

```sh
agtermctl workspace defaults --dir ~/mmee --agent "Claude Code" --target mmee
agtermctl workspace defaults --background ~/Pictures/mars.png --background-opacity 0.25 --target mmee
agtermctl workspace defaults --target mmee            # read back
```

Every new session there — ⌘N, `session+`, `session new`, a spawned peer — starts in that directory
running that agent unless the caller asked for something specific (`--cwd`, `--command`, a dropped
folder). The background is seeded onto the session at creation and then owned by it. An agent
deleted from Settings degrades the workspace to a plain shell.

## Spawning with a brief

A session for an agent with nothing to do is the most common way to waste one. `agx spawn` creates
the session and launches the agent with the brief as its first message — as an argument, not typed
into a TUI that may not be listening yet:

```sh
agx spawn --brief "Audit docs/ for stale paths; write findings to docs/audit.md incrementally" \
          --name "Docs audit" --workspace-name agx --cwd ~/agterm --agent claude
```

| flag | default |
|---|---|
| `--workspace-name W` / `--workspace ID` | the **caller's** workspace (not the one focused on screen); `--workspace-name` creates it if needed |
| `--cwd` | the workspace default, else home |
| `--agent` | `claude`; any installed profile (`codex`, `gemini`, `cursor-agent`, `opencode`, `mimo`, `hermes`, …) |
| `--foreground` | off — the new row opens in the background so the caller keeps its pane |
| `--json` | prints `{"id", "seeded", "foreground", "cwd_trusted"}` |

The brief is the agent's whole world: it cannot ask the caller back. State the goal, the
constraints, where to look, what "done" means, and tell it to write output to a file as it goes. A
directory the agent has never trusted stops at the agent's own trust dialog first; `spawn` warns
when it sees that coming. The same seeding runs under a scheduled session and a failover handoff.

## Scheduled sessions

```sh
agx schedule add --at "tomorrow 09:00" --brief "Run the nightly audit and post to #reports" \
                 --name "Nightly audit" --workspace-name mars
agx schedule list          # E2E9BCF9  2026-09-12T09:00:00+05:00  in 8h 8m  → life  "Ахангаран полив…"
agx schedule run <id>      # fire now
agx schedule cancel <id>
```

The app itself opens the session at that time and seeds it. Jobs persist in
`<state dir>/scheduled.json`; one due while the app was closed fires on the next launch; one overdue
by more than 24 h parks as `missed` for `run` or `cancel`. `--at` takes `+30m`, `+2h`, `+1d`,
`HH:MM`, `tomorrow [HH:MM]`, `YYYY-MM-DD [HH:MM]`, or ISO 8601. Each fire and miss posts a
notification and a `schedule.*` event; `tree` lists pending jobs under `scheduled`.

## Status glyphs and attention

One glyph per row, set by the agent's hooks through `agtermctl session status`:

| glyph | status | set when | cleared by |
|---|---|---|---|
| `●` blinking | active | a prompt was submitted, a tool ran | Escape or ⌃C in that pane |
| `✓` | completed | the turn finished | any keystroke in that pane |
| `⛔` | blocked | a permission or question prompt is waiting | any keystroke in that pane |
| — | idle | nothing to report | — |

Colors, shapes, the blocked sound, and auto-follow live in Settings ▸ Agent Status.

**Attention** has two readings. The title-bar `bell` counts sessions that are `⛔` or `✓`. The list
behind it (⌃⇧I) and ⌃⌥↑ / ⌃⌥↓ walk *every* session with a glyph — `⛔` first, then `●`, then `✓`,
newest change first within each — across all workspaces, ignoring the sidebar filter. Settings ▸
Agent Status ▸ Auto-follow switches to a session that just went `⛔` on its own once you have been
idle for the chosen time.

![Attention glyphs on the sessions that need you](../screenshots/agent-prompt.png)

## Failover

When a Claude Code pane stops on an API error, AGX acts instead of waiting for you to notice:

| what happened | what AGX does |
|---|---|
| "out of usage credits" for the current model | types `/model <next>` from the ladder (default `opus[1m]`, `sonnet[1m]`, skipping families already spent in this session), then `continue`. Same pane, same context and cache. |
| ladder spent, account limit, auth or billing error, process died mid-turn | opens `<name> → <agent>` beside it, same workspace and directory, running the handoff agent (Settings ▸ Agents ▸ Failover; default: the first connected agent whose binary differs) with a brief digested from the transcript: reason, last three prompts, last answer, transcript path |
| overloaded, server error | re-prompts after 20 s, at most three times in 30 min, then hands off |

Each step posts a notification, a `failover` event, and a `failover` read-back on the session node.
The signal is Claude Code's `StopFailure` hook, installed with the status hooks; a pane started
before the hook existed reports nothing, and only the crash path works for it. The ladder changes
Claude Code's default model as a side effect — the notification says which one the pane now runs.
An agent can trigger the handoff itself: `agtermctl session failure rate_limit --handoff`.

## Durable panes

A session started with a command (an agent, an `ssh`) runs it under a detached
[abduco](https://github.com/martanne/abduco) server named by the session id, so quitting,
relaunching, or crashing AGX reattaches the same process: the agent keeps its context and prompt
cache and finishes the turn it was in. Closing the session kills the server; a program that exited
while AGX was away is replaced on the next launch by the resume line.

- On by default (Settings ▸ General ▸ Durable agent panes; `session new --durable` for one session).
  Plain shells are not wrapped.
- `^\` (abduco's detach key) in a durable pane detaches the client, which closes the session — treat
  it like `exit`.
- Servers live in `<state dir>/abduco/`; `tree` reports `attached` per session after a relaunch.
  [Troubleshooting](../troubleshooting.md#a-durable-pane-comes-back-as-a-fresh-run-or-a-server-lingers)
  covers a pane that came back fresh.

## Usage

The sidebar footer shows the Claude account's 5-hour and 7-day pools, the live cost across sessions,
and a ⚠ for any session past the 200k-context tariff step. The numbers come from Claude Code's own
statusline: a statusline script that writes each session's metrics to
`~/.claude/agx-usage/<AGTERM_SESSION_ID>.json` feeds the panel; `agx usage` prints the same join:

```
AGX usage — 15 agent sessions  ·  account: 5h 11%  7d 66%
  ◐ Школа на Марсе в сентябре        [4431703C] Opus 5 (1M context)  23% (230k) ⚠2x  $49.83
  ✳ AGX user guide                   [531987A3] Opus 5 (1M context)  26% (260k) ⚠2x  $11.80
```

Without such a script the panel stays empty and nothing else changes.
