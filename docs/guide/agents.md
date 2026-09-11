# Agents

An agent in AGX is a program in a session that AGX knows a little about: how to hand it a first
message, how to resume it after a relaunch, which hooks make it report status, and what to do when it
stops on an error. Everything here is optional — an unknown CLI still runs in a pane — but with it
installed, thirty agents in the sidebar read like a to-do list instead of thirty terminals.

## Connected agents

Settings ▸ Agents holds the list. **Found on This Mac** probes `PATH` (plus `~/.local/bin`,
`~/.bun/bin`, and the Homebrew prefixes, which the GUI's own `PATH` lacks) for the CLIs AGX has a
profile for — Claude Code, Codex, Gemini, Cursor, OpenCode, Mimo, Hermes, Pi, Copilot, Aider, Amp,
Goose, Kimi, Qwen, Droid, Crush — and offers one-click Connect. **Add Custom Agent…** takes any name
and shell line. A connected agent is what a workspace default, `agx spawn --agent`, a scheduled
session, and failover handoff refer to by name.

What AGX knows per agent lives in one manifest, `agents/<binary>/agent.json` in the app's
`agent-status` resources: the seed flag for a first message, the resume line, the status hooks and
their dialect, the folder-trust file `agx spawn` probes. An agent with only a name and binary is
launch-only: it runs, it just reports nothing. Claude Code, Codex, and Gemini have the full set
(status, resume, context on start); OpenCode and Pi report status through a plugin; Cursor, OpenCode,
and Mimo resume; the rest launch.

## Workspace defaults

Right-click a workspace row ▸ Workspace Defaults…, or

```sh
agtermctl workspace defaults --dir ~/mmee --agent "Claude Code" --target mmee
agtermctl workspace defaults --background ~/Pictures/mars.png --background-opacity 0.25 --target mmee
agtermctl workspace defaults --target mmee            # read back
```

Every new session in that workspace — ⌘N, the row's `+`, `session new`, a spawned peer — starts in
that directory running that agent, unless the caller asked for something specific (`--cwd`,
`--command`, a dropped folder). The background image is seeded onto the session at creation and then
owned by it: restyling one session never edits the workspace, and editing the workspace never restyles
sessions already open. An agent deleted from Settings degrades the workspace to a plain shell.

## Spawning with a brief

A session for an agent with nothing to do is the most common way to waste one. `agx spawn` creates
the session and launches the agent with the brief as its first message — as an argument, not typed
into a TUI that may not be listening yet:

```sh
agx spawn --brief "Audit docs/ for stale paths; write findings to docs/audit.md incrementally" \
          --name "Docs audit" --workspace-name agx --cwd ~/agterm --agent claude
```

- `--workspace-name` creates the workspace if needed; without either workspace flag the new session
  lands in the caller's own workspace, not the one that happens to be focused.
- `--agent` accepts any installed profile (`claude`, `codex`, `gemini`, `cursor-agent`, `opencode`,
  `mimo`, `hermes`, …); default `claude`.
- `--foreground` selects the new session; by default it opens in the background so the caller keeps
  its pane.
- The brief is the agent's whole world. A spawned Claude Code pane gets `CLAUDE.md`, its skills, and
  `agx context` on start; agents without a session-start hook get an `agx context` pointer in front of
  the brief. It cannot ask the caller back, so the brief states goal, constraints, where to look, and
  what "done" means, and tells the agent to write output to a file as it goes.
- A directory the agent has never trusted (Claude's `~/.claude.json`, Codex, Gemini, Mimo each have
  a trust file) stops at the agent's own trust dialog before the brief; `spawn` warns when it sees that
  coming and reports `cwd_trusted` in `--json`.

The same seeding runs under a scheduled session and a failover handoff.

## Scheduled sessions

```sh
agx schedule add --at "tomorrow 09:00" --brief "Run the nightly audit and post to #reports" \
                 --name "Nightly audit" --workspace-name mars
agx schedule list
agx schedule run <id>       # fire now
agx schedule cancel <id>
```

The app itself opens the session at that time and hands the agent the brief. Jobs persist in
`<state dir>/scheduled.json`; one that was due while the app was closed fires on the next launch, one
overdue by more than 24 hours is parked as `missed` for `run` or `cancel` instead of firing days late.
`--at` takes `+30m`, `+2h`, `+1d`, `HH:MM`, `tomorrow [HH:MM]`, `YYYY-MM-DD [HH:MM]`, or ISO 8601.
Each fire and miss posts a notification and a `schedule.*` event; `tree` lists pending jobs under
`scheduled`.

## Status glyphs and attention

A session row carries one glyph, set by the agent's hooks through `agtermctl session status`:

| glyph | status | set when | cleared by |
|---|---|---|---|
| `●` (blinking) | active | a prompt was submitted, a tool ran | Escape or ⌃C in that pane |
| `✓` | completed | the turn finished | any keystroke in that pane |
| `⛔` | blocked | a permission or question prompt is waiting | any keystroke in that pane |
| — | idle | nothing to report | — |

Help ▸ Install Agent Status Hooks… installs these for every agent found on this Mac that has a
status integration (Claude Code and Gemini through their hooks JSON, Codex through its TOML hooks and
an adapter, Pi and OpenCode through a plugin) and shows one row per agent with a ✓ / ⚠ / – mark. Colors, shapes, the
blocked sound, and auto-follow are in Settings ▸ Agent Status.

**Attention** is the set of sessions that are `blocked` or `completed`. The title-bar `bell` (⌃⇧I)
lists them; ⌃⌥↑ / ⌃⌥↓ step through them without opening the list; Settings ▸ Agent Status ▸
Auto-follow switches to a blocked session on its own once you have been idle for the chosen time.

![Attention glyphs on the sessions that need you](../screenshots/agent-prompt.png)

## Failover

When a Claude Code pane stops on an API error, AGX acts instead of waiting for you to notice:

1. **Model ladder, same pane.** "Out of usage credits" for the current model → the app types
   `/model <next>` from the ladder (default `opus[1m]`, `sonnet[1m]`, skipping families already
   spent in this session) and then "continue". Context, cache, and history stay.
2. **Handoff to another agent.** Ladder spent, account limit hit, auth or billing error, or the agent
   process died mid-turn → a new session `<name> → <agent>` opens beside it in the same workspace and
   directory, running the handoff agent (Settings ▸ Agents ▸ Failover; default: the first connected
   agent whose binary differs) with a brief digested from the transcript: the reason, the last three
   prompts, the last answer, and the transcript path for more.
3. **Transient errors** (overloaded, server error) re-prompt after 20 s, at most three times in
   30 minutes, then hand off.

Each step posts a notification, a `failover` event, and a `failover` read-back on the session node.
The signal is Claude Code's `StopFailure` hook, installed with the status hooks; a pane started under
an app that predates the hook never reports, and only the crash path works for it. The ladder changes
Claude Code's default model as a side effect — the notification says which one the pane now runs.
An agent can trigger the handoff itself: `agtermctl session failure rate_limit --handoff`.

## Durable panes

A session started with a command (an agent, an `ssh`) runs that program under a detached
[abduco](https://github.com/martanne/abduco) server named by the session id, so quitting,
relaunching, or crashing AGX reattaches the same process. The agent keeps its context and prompt
cache and finishes the turn it was in; the screen repaints on attach. Closing the session kills the
server; a program that exited while AGX was away is replaced on the next launch by the resume line.
On by default (Settings ▸ General ▸ Durable agent panes; `session new --durable` for one session).
Plain shells are not wrapped. `^\` in a durable pane detaches the client, which closes the session —
treat it like `exit`. Servers live in `<state dir>/abduco/`; `tree` reports `attached` per session
after a relaunch, and [Troubleshooting](../troubleshooting.md#a-durable-pane-comes-back-as-a-fresh-run-or-a-server-lingers)
covers the case where a pane came back fresh.

## Usage

The sidebar footer shows the Claude account's 5-hour and 7-day pools, the live cost across sessions,
and a ⚠ for any session past the 200k-context tariff step. The numbers come from Claude Code's own
statusline: a statusline script that writes each session's metrics to
`~/.claude/agx-usage/<AGTERM_SESSION_ID>.json` feeds the panel; `agx usage` prints the same join in
the terminal. Without such a script the panel stays empty and nothing else changes.
