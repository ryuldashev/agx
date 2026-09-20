# Why AGX

One coding agent fits in a terminal tab. Ten do not: you lose which tab is which, which one stopped
to ask a question twenty minutes ago, and which one quietly ran out of quota mid-task. AGX exists for
that day, and for nothing else.

## Three problems, three answers

| the problem with N agents in tabs / tmux | what AGX does about it |
|---|---|
| **You cannot see them.** Ten panes look the same; the one waiting on a permission prompt looks exactly like the one still working. | The sidebar is a status board: `●` working, `✓` done, `⛔` waiting for you, set by the agent's own hooks. ⌃⌥↓ jumps to the next one that needs you; a collapsed project shows the loudest glyph inside. [A day](a-day.md), [Agents › Status](agents.md#status-glyphs-and-attention). |
| **They cannot see each other.** Claude Code has no idea a Codex session is running next door, cannot open a peer with a task, and cannot show you a document except by pasting it into the chat. | Every pane can drive the terminal it runs in: `agx context` reads the whole board, `agx spawn --brief` opens a peer already working, `agx reader` renders a document beside the shell, `agx schedule` opens a session tomorrow. [Driving AGX](driving.md). |
| **They die at the wrong moment.** Quit the app and the turn is gone; hit the usage limit and the task sits until you notice. | A session's process survives quit, relaunch, and crash (durable panes). When a model's pool is spent AGX switches models; when the account is spent it hands the task to another agent with a brief from the transcript. [Agents › Durable](agents.md#durable-panes), [Failover](agents.md#failover). |

The terminal underneath is [Ghostty](https://ghostty.org) through [agterm](https://agterm.com), so
none of this costs rendering speed, and every shortcut and every button has a control-API twin an
agent can call.

## What AGX is not

- **Not an orchestrator.** It does not decide what agents do, split tasks, or merge results. An agent
  that wants a peer writes the brief itself; a human who wants three reviews opens three sessions.
- **Not a chat client.** Agents run as the TUIs they already are — Claude Code, Codex, Gemini — in a
  real pty. AGX adds a sidebar, hooks, and a socket; it never sits between you and the agent's input.
- **Not a sandbox.** A pane is your shell with your permissions. An agent in it can do anything you
  can, including on the UI (see [what an agent cannot do](driving.md#what-an-agent-cannot-do) for the
  short list of real limits). Guardrails belong to the agent's own permission mode.

If you run one agent at a time, a plain terminal is fine. AGX starts paying off at three.
