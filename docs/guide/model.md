# The model

Everything in AGX is one of six things, and each is an object a script can address by id. Learn the
six and the sidebar, the palettes, `agtermctl tree`, and `agx context` all read the same way.

| thing | holds | make / show | id in `tree` |
|---|---|---|---|
| **window** | workspaces, its own sidebar | ⌘⌥N | `window` |
| **workspace** | sessions for one project | ⌘⇧N, `workspace new "<NAME>"` | `workspace` |
| **session** | one shell or agent, a sidebar row | ⌘N, `session new` | `session` |
| **split** | a second shell beside/below, same row | ⌘D / ⌘⇧D | `surfaces[kind: right]` |
| **scratch** | a third shell over the session | ⌘J, `session scratch on` | `scratch: true` |
| **overlay** | one program over a session, gone on exit | `session overlay open`, `agx run` | `overlay: true` |

Over the whole window, not a session: the **quick terminal** (⌃`) and the **dashboard** (⌘⇧G).

## Window

Most days one is enough; a second (⌘⌥N) is for a second screen or a context you want physically
apart. Addressed by id or `active`; geometry, fullscreen, zoom, minimize, and sidebar state are all
readable and settable over the control API.

## Workspace

A named group of sessions for one project: `mars`, `agx`, `cambridge`. Rename or delete from the
row's context menu, reorder by drag. Two things live on the workspace, not on its sessions:

- **Workspace Defaults** (right-click ▸ Workspace Defaults…) — the directory new sessions open in,
  the connected agent they run, a background image. [Agents › Workspace defaults](agents.md#workspace-defaults).
- **Focus** — mark workspaces focused and flip the sidebar's `filter` toggle to see only those.

A collapsed row shows its session count and the loudest status inside (`⛔` over `✓` over `●`), so
a background project that needs you is visible without expanding it.

## Session

One running shell or agent with a name, a directory, and its own scrollback: the row in the sidebar,
running whether or not you are looking. ⌘N opens one with the workspace's defaults; ⌘O opens one in
a directory you pick, as does dropping a folder on a workspace row. ⌘W closes it — ⌘Z within 3 s
undoes that, ⌘⇧T reopens the last closed item later, and a reopened agent session comes back
running its agent's resume line (`claude --resume <id> --fork-session`), not a bare shell.

What a session carries, and where each is read back:

| state | set by | read back |
|---|---|---|
| name | you (double-click, Rename) or the program's title — an agent's `◐ Refactor payroll` lands here | `name`, `title` |
| status glyph `●` `✓` `⛔` | the agent's hooks; cleared by your keystroke | `status`, `statusBlink` |
| flag (⌘⇧F) | you; the sidebar's `flagged` view shows only these | `flagged` |
| unseen | notifications posted while you were elsewhere; badge on the row and Dock | `unseen` |
| durable | a command session's process survives a restart | `durable`, `attached` |

## Split

A second shell beside (⌘D) or below (⌘⇧D) the first, sharing the row, the name, and the status. The
title-bar `split` button cycles **none → both → hidden with the main pane on screen**; hiding never
kills the second shell — only its own `exit` or Close Split (⌃⇧P) does. ⌃1 / ⌃2 focus main / split
and, on a hidden split, choose which is shown. ⌘⇧⏎ zooms the focused pane to the window. The split
pane is also where the [reader](reader.md) draws a document.

## Scratch

A third shell covering the whole session for a quick aside (⌘J). It keeps its own scrollback and a
persistent command if you gave it one (`session scratch on --command "ssh -N …"`), which makes it
the place for a tunnel or a dev server the main pane should not block on. No title-bar button —
that slot is `zoom` — but ⌘J, the palette, and the control API reach it.

## Overlay

One program in a temporary terminal over a session, full-size or floating (`--size-percent`), gone
when it exits, the shell underneath untouched. Edit Keymap and Edit ghostty.conf open the editor
this way; `agx run` uses it to run a command and capture its output; a HUD (`session hud open`) is a
passive message panel in the same slot. One overlay per session at a time.

![A floating overlay over a session](../screenshots/floating-overlay.png)

## Stacking

Quick terminal and dashboard over the window; scratch over the session; overlay and zoom over the
pane. While something covers a session, `split` first removes the cover.

![Dashboard](../screenshots/dashboard.png)

## What survives a restart

| kept | how |
|---|---|
| windows, workspaces, sessions, names, directories, font size, split state and ratio, flags, workspace defaults | `~/Library/Application Support/agx/windows/<id>.json` |
| **the agent process itself** (durable sessions, default for every command session) | the same PID reattaches with its context, cache, and the turn it was in; `attached: true` in `tree` |
| a non-durable command session | re-run: the agent's resume line if the hooks pinned one, else the original command (Settings ▸ General ▸ Restore running commands) |
| **not kept** | overlays, scratch content, the reader, the quick terminal |
