# Driving AGX from an agent

An agent running in an AGX pane is not sandboxed in a terminal: it is operating the user's UI. It
can see which sessions are open and who needs attention, open a peer session with a task, run a
command in its own side pane, show a document, and schedule work for later — the same control
socket the user's shortcuts go through. `agx` is the agent-facing wrapper over `agtermctl`; this
chapter is what an agent should know before its first tool call.

## What an agent gets on start

Every pane's environment carries `AGTERM_ENABLED=1`, `AGTERM_SOCKET` (this app's control socket —
so a command from a pane addresses the app that spawned it, even with two builds installed),
`AGTERM_SESSION_ID`, `AGTERM_WORKSPACE_ID`, `AGTERM_WINDOW_ID`, `AGTERM_PANE` / `AGTERM_PANE_ID`, and
`TERM_PROGRAM=agterm`. The hooks from Help ▸ Install Agent Status Hooks… act only when
`AGTERM_ENABLED` is set, so they cost nothing outside AGX.

For Claude Code, Codex, and Gemini a session-start hook injects `agx context` into the first turn
and pins the resume line the pane will run after a relaunch. Other agents get a one-line pointer to
`agx context` in front of a spawned brief.

## agx context

```
agx context [--json]
```

The self-description: who I am (session, workspace, pane, cwd, running program), what the user sees
now (frontmost window, focused session, sidebar and quick-terminal state), every open session with
its status and flags, the manifest of what an agent can drive from here, and the honest list of what
it cannot. Call it again whenever the picture may have changed — it is the read side of everything
below.

## agx spawn

```
agx spawn --brief "<task>" [--name T] [--workspace-name W | --workspace ID] [--cwd PATH]
          [--agent claude|codex|gemini|…] [--foreground] [--json]
```

Opens a peer session and launches the agent with the brief as its first message. The rules for a
brief and the trust probe are in [Agents › Spawning with a brief](agents.md#spawning-with-a-brief).
Use it when the user should *see* and drive the work; an in-turn subagent (the Agent tool) is
invisible in the sidebar, shares the caller's turn, and returns to the caller — right for
token-heavy research, wrong for work the user will want to steer.

## agx run

```
agx run "<shell cmd>" [--pane split] [--keep]
```

Runs a finite command in an overlay on the caller's own pane and prints its output and exit code.
The user watches it happen; the agent gets the result. For something that must stay alive — a
tunnel, a dev server — use the scratch instead: `agtermctl session scratch on --command "<cmd>"`,
read it later with `agtermctl session text --pane scratch`. A pane already has a real, unrestricted
shell beside it; an agent should run the shell step itself, not hand it back to the user.

## agx schedule

```
agx schedule add --at <time> --brief "<task>" [--name T] [--workspace-name W] [--cwd PATH]
agx schedule list | cancel <id> | run <id>
```

Delegation with a delay: the app opens the session at the time and seeds it. Details in
[Agents › Scheduled sessions](agents.md#scheduled-sessions).

## agx reader

```
agx reader <path.md> [--target ID]
agx reader close [--target ID]
```

Shows a markdown file in the caller's right pane, re-rendering as the file changes. Write the plan or
report once, open it once, keep editing — the pane follows. Do not paste long markdown into the chat
when the user should read it rendered. [The reader pane](reader.md).

## agtermctl essentials

The full verb set is agterm's ([Help ▸ agterm Control API Reference…](https://agterm.com/commands));
these are the ones a day with agents actually uses:

```sh
agtermctl tree --json                                   # the whole model, read-back for everything
agtermctl session text --target <id|prefix> [--lines N] # read another session's terminal
agtermctl session type --target <id> --select "text\n"  # type into it (\n submits)
agtermctl session select --target <id>                  # bring it to front
agtermctl session status active|completed|blocked|idle [--blink]   # my own glyph
agtermctl session hud open "<message>" --target <id> [--detail …] [--spinner]  # passive panel
agtermctl session overlay open --target <id> -- <cmd>   # a program over a session
agtermctl session failure rate_limit --handoff          # hand my task to another agent now
agtermctl workspace new "<NAME>"                        # positional, not a flag
agtermctl notify "<body>" [--title "…"]                 # desktop notification tied to this session
printf '%s\n' a b | agtermctl pick --prompt "Which?"     # native picker, blocks until chosen
agtermctl events                                        # stream status/session/schedule/failover events
```

Targets are a session id, a unique prefix, or `active`. `session type` returns when the keys are
queued, so a `session text` right after it races the program. Positional arguments where the CLI
says so: `session move <workspace>`, `workspace new "<NAME>"`, `notify "<body>"`.

## Hooks and the skill

- **Help ▸ Install Agent Status Hooks…** merges, per agent, the hooks its manifest declares:
  status on prompt / tool / stop / permission-prompt, `SessionStart` for context and resume,
  `StopFailure` for failover. Marker-guarded, so rerunning is safe; each script is a no-op outside
  AGX and always exits 0, so it can never block a turn. The wrappers bake in the bundled
  `agtermctl` and `agx` paths, so nothing has to be on `PATH`.
- **Help ▸ Install Agent Skill…** installs the agterm skill for Claude Code and Codex: the control
  model, the addressing rules, and every `agtermctl` command, so an agent can build its own layout
  without being told the API. The same skill ships as a plugin
  (`claude plugin install agterm@agterm`); install by one route, never both.
- **Help ▸ Install Command Line Tool…** links `agtermctl` and `agx` into `/usr/local/bin` for
  shells outside AGX. Inside a pane the hooks and `agx context` already know where the binaries are.

## The action journal

`<state dir>/journal.jsonl` records every ⌘/⌃ chord the app saw (with the character the layout
produced and whether the chord was consumed), every built-in action with its origin (keymap or
palette), every mutating control request (command, target, caller), and the scratch / split / close
state flips. Plain typing is never recorded. When the UI did something nobody remembers asking for
— a scratch that appeared over an agent, a split that hid the wrong pane — the journal answers
"what drove it" instead of reconstructing it:

```sh
tail -f ~/Library/Application\ Support/agx/journal.jsonl
```

## What an agent cannot do

- **Message another agent structurally.** `session type` is fire-and-forget stdin: you type into its
  input; there is no request/reply. To get an answer, poll `session text` on it.
- **See pixels.** There is no window screenshot. An agent reads terminal buffers and `tree`, not the
  chrome — which is what the ⌥ hint panel and `docs/ui-lexicon.md` tokens are for when the user
  reports a button.
- **Edit settings on disk.** `settings.json` is held in memory and rewritten at quit, silently
  reverting the edit. Change UI state through `agtermctl` or the Settings window.
- **Spawn a bare binary.** A session started with `--command` execs that argv under the GUI's
  minimal `PATH`; a binary not on it exits 127. Workspace defaults and `agx spawn` resolve the agent
  for you; a hand-written command should be a full path or a `zsh -lc '…'` line.
