# Settings

⌘, opens seven tabs. Four matter for a day with agents — General, Agents, Agent Status,
Notifications — the rest are terminal preferences. Settings live in memory and are written at quit:
change them here or over `agtermctl`, never by editing `settings.json` while the app runs.

| tab | what lives there |
|---|---|
| **General** | mouse (scroll speed, right-click pastes, click expands a workspace row); copy clean-up (drop a TUI's frame gutter, trailing padding, shared indent; flash on copy); **Sessions**: where a new session opens when the workspace pins nothing, **Restore running commands on restart**, **Durable agent panes**, confirm before closing, allow undo after closing; whether `~/.config/ghostty/config` is chained under `~/.config/agx/ghostty.conf` ([Troubleshooting](../troubleshooting.md#changing-ghostty-settings)) |
| **Appearance** | font and size, theme (the fork ships `agx`; upstream's palette under its own name), follow system appearance, toolbar mode (normal / compact / hidden), background opacity and blur, sidebar tint and font size, palette font size, inactive-pane and backdrop muting, whether workspace background art is mirrored into the split pane |
| **Interface** | show / hide each title-bar and sidebar control (`sidebar`, session name, window name, `recent`, `zoom`, `split`, `dash`, `quick`, `workspace+`, `session+`, `flagged`, `filter`, the row's add-session button); a hidden control leaves the ⌥ panel too; **Show sidebar only in the active window** |
| **Notifications** | banners, badges, Dock bounce (none / once / until focused), sound, the `bell`. With banners off, `agtermctl notify` still marks the row unseen and says so in its reply; macOS must have granted permission (System Settings ▸ Notifications ▸ agx) and a Focus mode suppresses banners system-wide |
| **Agents** | **Connected** (the named list workspace defaults, `agx spawn --agent`, scheduled sessions and handoff refer to); **Found on This Mac** with Connect and Rescan; **Failover**: switch model when the pool is spent, the model ladder (`/model` order, `[1m]` allowed), hand off when the ladder is spent or the agent crashes, which agent |
| **Agent Status** | colors and shapes per status (also per call: `session status --color/--shape`); blocked sound; **Auto-follow** after 5 s – 5 min idle to a session that just went `⛔`; **Auto-follow away from a running session** |
| **Key Mapping** | the keymap directory (default `~/.config/agx`; changing it reloads) and the parser's diagnostics — a malformed line, a dropped binding, a chord conflict. Empty is the goal |

Two couplings worth knowing:

- **Durable needs Restore.** With durable panes on and restore off, a restored pane comes back a
  plain shell with its server orphaned until the session is closed. Keep both on.
- **A workspace keeps its own agent line.** Renaming or editing a connected agent in Settings does
  not reach workspaces that already pinned it; deleting the agent degrades them to a plain shell.
  Re-pick it in Workspace Defaults.

