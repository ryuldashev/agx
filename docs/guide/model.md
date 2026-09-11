# The model

Everything in AGX is one of six things, and every one of them is also an object a script can address
by id. Learn the six and the sidebar, the palettes, the control API, and `agx context` all read the
same way: a window holds workspaces, a workspace holds sessions, a session owns its panes and whatever
is drawn over them.

## Window

A top-level macOS window with its own sidebar tree. Most days one window is enough; a second one
(⌘⌥N) is for a second screen or a second context you want physically apart. Windows are addressed
by id or `active`; a window's state — geometry, fullscreen, zoom, minimize, sidebar — is readable and
settable over the control API.

## Workspace

A named group of sessions for one project: `mars`, `agx`, `cambridge`. Create one with ⌘⇧N, rename
or delete it from the row's context menu, reorder by drag. Two things live on the workspace, not on
its sessions:

- **Workspace Defaults** (right-click ▸ Workspace Defaults…): the directory new sessions open in, the
  connected agent they run, and a background image every session there starts with. See
  [Agents › Workspace defaults](agents.md#workspace-defaults).
- **Focus**: mark workspaces as focused and flip the sidebar's `filter` toggle to see only those.
  Membership is model state; the filter is a view.

A collapsed workspace row shows how many sessions it holds and the most demanding status among them
(`⛔` beats `✓` beats `●`), so a background project that needs you is visible without expanding it.

## Session

One running shell (or agent) with a name, a working directory, and its own scrollback. It is the row
in the sidebar and it keeps running while you look at another one. ⌘N opens one in the current
workspace, using that workspace's defaults; ⌘O opens one in a directory you pick; dropping a folder
on a workspace row does the same. ⌘W closes it (with a 3-second undo, ⌘Z), ⌘⇧T reopens the last closed
item — a reopened agent session comes back running its agent's `resume` line, not a bare shell.

A session carries the state other layers read:

- **Name** — set by you (double-click, or Rename) or by the program's title (an agent's title
  `◐ Refactor payroll` lands here). `agx context` and `agtermctl tree` print it.
- **Status glyph** — `●` active, `✓` completed, `⛔` blocked, nothing for idle. Set by the agent's
  hooks; cleared by your keystroke. [Agents › Status glyphs](agents.md#status-glyphs-and-attention).
- **Flag** (⌘⇧F) — your own mark. The sidebar's `flagged` toggle shows only flagged sessions.
- **Unseen** — notifications posted while you were elsewhere; the badge on the row and the app icon.
- **Durable** — a command session survives an app restart with its process intact.
  [Agents › Durable panes](agents.md#durable-panes).

## Split

A session can hold a second shell beside (⌘D) or below (⌘⇧D) the first. Both share the one sidebar
row, the one name, the one status. The title-bar `split` button cycles three states: no split →
both panes → split hidden with the **main pane** on screen. Hiding never kills the second shell;
only its own `exit` or Close Split (⌃⇧P palette) does. ⌃1 / ⌃2 focus the main / split pane and,
on a hidden split, choose which pane is shown. ⌘⇧⏎ zooms the focused pane to the whole window.

The split pane is also where the [reader](reader.md) draws a document.

## Scratch

A third shell that covers the whole session for a quick aside (⌘J, or `session scratch on`). It
keeps its own scrollback and a persistent command if you gave it one (`--command "ssh -N …"`), so it
is the place for a tunnel or a dev server the main pane should not block on. The title bar no longer
carries a scratch button — that slot is `zoom` — but ⌘J, the palette, and the control API all reach it.

## Overlay

One program in a temporary terminal over a session: full-size or floating, gone when the program
exits, the shell underneath untouched. Edit Keymap and Edit ghostty.conf open the editor this way;
`agx run` uses it to run a command and capture its output; a HUD (`session hud`) is a passive panel
in the same slot. One overlay per session at a time.

![A floating overlay over a session](../screenshots/floating-overlay.png)

## Quick terminal and dashboard

Two things sit over the whole window rather than a session. The **quick terminal** (⌃`) drops a
shell over the frontmost window from anywhere, opening in the active session's directory. The
**dashboard** (⌘⇧G) tiles every live session's output into one view-only grid; click a tile to drop
into it.

![Dashboard](../screenshots/dashboard.png)

Stacking order: quick terminal and dashboard over the window, scratch over the session, overlay and
zoom over the pane. While something covers a session, the `split` button first removes the cover.

## What survives a restart

- Windows, workspaces, sessions, names, directories, font size, split state and ratio, flags,
  workspace defaults: all restored from `windows/<id>.json`.
- **The agent process itself**, when the session is durable (default for every session started with
  a command): the same PID reattaches, with its context, prompt cache, and the turn it was in the
  middle of. Whether a session reattached or restarted is read back as `attached` in `tree`.
- A non-durable command session is re-run: its agent's `resume` line (`claude --resume <id>` for
  Claude Code) when the hooks pinned one, else the original command, gated by Settings ▸ General ▸
  Restore running commands.
- Not restored: overlays, scratch content, the reader, the quick terminal.
