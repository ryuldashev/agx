# AGX Guide

AGX is a macOS terminal for running many coding agents at once. Each agent lives in a named
session inside a named workspace, reports whether it is working, done, or waiting on you, survives
an app restart with its process intact, and can drive the terminal it runs in: open a peer session
with a task, schedule one for tomorrow, show you a document beside its shell. This guide is about
that day — what the pieces are, how agents use them, and where to look when something is off.

Under the hood AGX is a fork of [agterm](https://agterm.com). The low-level control API — every
`agtermctl` command with its arguments and read-back — is documented there
([agterm.com/commands](https://agterm.com/commands), Help ▸ agterm Control API Reference…) and is not
repeated here.

## AGX in 5 minutes

1. **Install the tools.** Help ▸ Install Command Line Tool… links `agtermctl` and `agx` into
   `/usr/local/bin`. Help ▸ Install Agent Status Hooks… wires the agents found on this Mac so their
   sessions show a status glyph, get `agx context` on start, resume after a relaunch, and fail over.
   Help ▸ Install Agent Skill… teaches Claude Code and Codex the control model. All three are safe
   to rerun.
2. **Connect an agent.** Settings ▸ Agents lists what was found on this Mac; Connect the ones you
   use. A connected agent is a name plus a shell line — anything runnable qualifies.
3. **Make a workspace per project** (⌘⇧N) and pin its directory and agent: right-click the workspace
   row ▸ Workspace Defaults…. From then on ⌘N in that workspace opens the agent in that directory.
4. **Read the sidebar, not the panes.** `●` working, `✓` finished, `⛔` waiting for you; the bell in
   the title bar and ⌃⌥↑/↓ step through the sessions that need you. A collapsed workspace shows its
   session count and the loudest status inside.
5. **Let the agent drive.** Inside a pane, `agx context` describes the UI the agent is in;
   `agx spawn --brief "…"` opens a peer session already working on a task; `agx reader plan.md`
   shows a document beside the shell; `agx schedule add --at "tomorrow 09:00" --brief "…"` opens
   one later, even after a relaunch.
6. **Quit whenever.** A session running an agent keeps its process across quit, relaunch, and
   crash; the same conversation, cache, and unfinished turn come back. Hold ⌥ to see the name and
   shortcut of every button on screen.

![AGX](../screenshots/main.png)

## Chapters

- [The model](model.md) — window, workspace, session, split, scratch, overlay, reader; what a restart keeps.
- [Agents](agents.md) — connected agents, workspace defaults, spawn with a brief, scheduled sessions,
  status glyphs and attention, failover, durable panes, usage.
- [Driving AGX from an agent](driving.md) — `agx context/spawn/run/schedule/reader`, the essential
  `agtermctl` verbs, hooks and the skill, the action journal, what an agent cannot do.
- [The reader pane](reader.md) — a live-reloading markdown document in the split pane.
- [Keyboard, palettes and ⌥ hints](keyboard.md) — palettes, the ⌥ cheat sheet, chords, custom keymap.
- [Settings](settings.md) — every tab, what matters for agents.
- [Troubleshooting](../troubleshooting.md) — logs, keymap diagnostics, durable panes, notifications, TCC.
