# Settings

⌘, opens seven tabs. Most of them are ordinary terminal preferences; the ones that matter for a day
with agents are General (durable panes, restore), Agents (who is connected, failover), Agent Status
(how a glyph looks and whether the app follows it), and Notifications. Settings are held in memory
and written at quit — change them here or over `agtermctl`, never by editing `settings.json` while
the app runs.

## General

- **Mouse** — scroll speed, right-click pastes, whether clicking a workspace row expands it.
- **Copy** — clean up copied text (drops a TUI's frame gutter, trailing padding, shared indent);
  flash the pane on copy.
- **Sessions** — where a new session opens when the workspace pins nothing (home, the current
  session's directory, or a custom one); **Restore running commands on restart**; **Durable agent
  panes** ([Agents › Durable panes](agents.md#durable-panes) — durable needs restore on, or a
  restored pane comes back a plain shell with its server orphaned until the session is closed);
  confirm before closing a session; allow undo after closing sessions and workspaces.
- **Ghostty Config** — whether `~/.config/ghostty/config` is in the chain under
  `~/.config/agx/ghostty.conf` ([Troubleshooting › Changing ghostty settings](../troubleshooting.md#changing-ghostty-settings)).

## Appearance

Font and default size, theme (the fork ships `agx`, upstream's neutral palette under its own file),
follow system appearance, toolbar mode (normal / compact / hidden), background opacity and blur,
sidebar tint and font size, palette font size, how much an inactive pane and the backdrop are muted,
and whether a workspace's background art is mirrored into the split pane.

## Interface

Show or hide each title-bar and sidebar control: sidebar toggle, session name, window name, recent
sessions, pane zoom, split view, dashboard, quick terminal, new workspace, new session, flagged view,
workspace filter, the workspace row's add-session button. A hidden control drops out of the ⌥ hint
panel too. **Show sidebar only in the active window** for multi-window setups.

## Notifications

Banners, badges, Dock bounce (none / once / until focused), the notification sound, and the
attention indicator (the `bell`). With banners off, `agtermctl notify` still counts as unseen on the
row and says so in its reply; macOS must also have granted permission (System Settings ▸
Notifications ▸ agx) and a Focus mode suppresses banners system-wide.

## Agents

**Connected** — the named list a workspace default, `agx spawn --agent`, a scheduled session, and a
handoff refer to. **Found on This Mac** — the profiles whose binary is on `PATH` (with the
directories agents actually install into added), Connect in one click, Rescan after installing one.
**Failover** — switch model and continue when an agent runs out of usage; the model ladder (tried in
order via `/model`, `[1m]` allowed); hand the task to another agent when the ladder is spent or the
agent crashes; which agent (default: the first connected one whose binary differs).
[Agents › Failover](agents.md#failover).

## Agent Status

**Colors and Shapes** per status (also settable per call with `session status --color/--shape`).
**Blocked sound** — plays only for `blocked`. **Auto-follow** — after the chosen idle time (5 s to
5 min) the app selects a session that just went `blocked`; **Auto-follow away from a running
session** decides whether it does so even while the session you are in is still `active`.

## Key Mapping

The keymap directory (default `~/.config/agx`; changing it reloads), and the parser's diagnostics
for `keymap.conf` — a malformed line, a dropped binding, a chord conflict. Empty is the goal.
[Keyboard › Custom keymap](keyboard.md#custom-keymap).
