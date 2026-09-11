# AGX Guide

AGX is a macOS terminal for running many coding agents at once. Each agent lives in a named session
inside a named workspace, reports whether it is working, done, or waiting on you, survives an app
restart with its process intact, and can drive the terminal it runs in: open a peer session with a
task, schedule one for tomorrow, show you a document beside its shell.

Under the hood AGX is a fork of [agterm](https://agterm.com). The low-level control API — every
`agtermctl` command with its arguments and read-back — is documented there
([agterm.com/commands](https://agterm.com/commands), Help ▸ agterm Control API Reference…) and is
not repeated here.

## AGX in 5 minutes

1. **Install the tools.** Help ▸ Install Command Line Tool… links `agtermctl` and `agx` into
   `/usr/local/bin`. Help ▸ Install Agent Status Hooks… wires the agents found on this Mac so their
   sessions show a status glyph, get `agx context` on start, resume after a relaunch, and fail over.
   Help ▸ Install Agent Skill… teaches Claude Code and Codex the control model. All three are safe
   to rerun; [First run](first-run.md) lists every file they touch.
2. **Connect an agent.** Settings ▸ Agents lists what was found on this Mac; Connect the ones you
   use. A connected agent is a name plus a shell line — anything runnable qualifies.
3. **Make a workspace per project** (⌘⇧N) and pin its directory and agent: right-click the row ▸
   Workspace Defaults…. From then on ⌘N in that workspace opens the agent in that directory.
4. **Read the sidebar, not the panes.** `●` working, `✓` finished, `⛔` waiting for you; the `bell`
   in the title bar and ⌃⌥↑ / ⌃⌥↓ step through the sessions that need you. A collapsed workspace
   shows its session count and the loudest status inside.
5. **Let the agent drive.** Inside a pane, `agx context` describes the UI the agent is in;
   `agx spawn --brief "…"` opens a peer already working on a task; `agx reader plan.md` shows a
   document beside the shell; `agx schedule add --at "tomorrow 09:00" --brief "…"` opens one later.
6. **Quit whenever.** A session running an agent keeps its process across quit, relaunch, and crash;
   the same conversation, cache, and unfinished turn come back. Hold ⌥ to see the name and shortcut
   of every button on screen.

![AGX](../screenshots/main.png)

## Chapters

1. [Why AGX](why.md) — the three problems with N agents in tabs, and what AGX is not.
2. [A day with several agents](a-day.md) — one working day, step by step, with what is on screen and
   the command behind it. Start here.
3. [First run](first-run.md) — permissions, the three installers file by file, how to undo each,
   Settings ▸ Agents, the first spawn.
4. [The model](model.md) — window, workspace, session, split, scratch, overlay; what a restart keeps.
5. [Agents](agents.md) — connected agents, workspace defaults, spawn with a brief, scheduled
   sessions, status glyphs and attention, failover, durable panes, usage.
6. [Driving AGX from an agent](driving.md) — the first five commands with real output, why `active`
   is not you, the `agx` verbs, `agtermctl` essentials, the journal, what an agent cannot do.
7. [The reader pane](reader.md) — a live-reloading markdown document in the split pane.
8. [Keyboard, palettes and ⌥ hints](keyboard.md) — palettes, the ⌥ cheat sheet, chords, custom keymap.
9. [Settings](settings.md) — the seven tabs in one table, and two couplings that bite.
10. [Troubleshooting](../troubleshooting.md) — logs, keymap diagnostics, durable panes,
    notifications, TCC.
