# First run

Twenty minutes from a fresh download to an agent that spawned a peer. Every step here says what is
written where, so you can undo it; none of it is required — AGX is a working terminal before any of
it, and all three installers can be rerun after an update.

## 1. Two dialogs on first launch

1. **Welcome** — two checkboxes (agent skill, agent status hooks) and Install / Later. Later loses
   nothing: both live under Help.
2. **Permissions macOS asks agx for** (Help ▸ Permissions… any time). Read it once; it explains the
   one thing about macOS that will otherwise confuse you for months.

### Why macOS says "agx would like to access…"

A command in a pane is a child process of agx, so TCC credits its requests to agx. `find ~` walks
into `~/Music` and the dialog says *agx wants your music library*; `screencapture` asks for *Screen
Recording* in agx's name. The app itself reads none of these.

| area | who actually asks | how it is granted |
|---|---|---|
| Music/media, Photos, Desktop, Documents, Downloads | any tool touching that folder | the wall raises the real macOS dialog for the boxes you tick |
| Full Disk Access, Accessibility, Screen Recording | tools reading protected data, driving other apps, grabbing the screen | System Settings only — the wall opens the right pane |

A TCC dialog freezes the process that tripped it, so **What's running now…** on the wall lists
`workspace ▸ session — command` for every pane; the culprit is whichever one is stuck. Grants stick
across updates because the app is signed with a stable Developer ID; an ad-hoc build asks again
after every rebuild.

## 2. Help ▸ Install Command Line Tool…

| writes | what |
|---|---|
| `/usr/local/bin/agtermctl`, `/usr/local/bin/agx` | symlinks into the app bundle (one admin prompt if the directory is not writable) |

Needed only for shells *outside* AGX; inside a pane the hooks bake the bundle paths in. It replaces
whatever sits at those two names without asking. **Undo:** `rm /usr/local/bin/agtermctl /usr/local/bin/agx`.

## 3. Help ▸ Install Agent Status Hooks…

This is what turns the sidebar into a status board. Per agent it merges the hooks that agent's
manifest declares (`Contents/Resources/agent-status/agents/<binary>/agent.json`), only for agents
whose config directory already exists, and shows one row per agent with ✓ / ⚠ / –.

| writes | what | your existing content |
|---|---|---|
| `~/.config/agx/agent-status/` | the hook scripts, recopied on every run with the bundle's `agtermctl`/`agx` paths baked in | replaced (nothing of yours lives here) |
| `~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish` | one `source` line between `# >>> agterm agent-status >>>` markers | appended once; never edited |
| `~/.claude/settings.json`, `~/.gemini/settings.json` | seven Claude hooks (`UserPromptSubmit`, `PostToolUse`, `Stop`, `Notification` permission_prompt, two `SessionStart`, `StopFailure`); Gemini's set | **additive**: appended to each event's array, your entries untouched; `settings.json.bak` (the previous contents, overwritten on each rerun) written beside first |
| `~/.codex/config.toml` | Codex's hooks table | `.bak` beside; **skipped** if the file already has its own `[hooks]` |
| `~/.config/opencode/plugins/agterm-status.js`, `~/.pi/agent/extensions/agterm-status.ts` | a plugin file | overwritten, no backup (carries no user state) |

Each script starts with `[ -n "$AGTERM_SESSION_ID" ] || exit 0` and always exits 0: outside AGX it
is a no-op, and inside it can never block a turn. Rerunning is idempotent (a hook whose command
already points into `agent-status/` is not added twice). Rerun it after moving the app — the baked
paths point at the bundle that installed them.

**Undo** (there is no uninstaller): restore the `.bak`, or delete every hook entry whose command
contains `agent-status/`; delete the marked block in the rc files; `rm -rf ~/.config/agx/agent-status`.

## 4. Help ▸ Install Agent Skill…

| writes | what |
|---|---|
| `~/.claude/skills/agterm/`, `~/.codex/skills/agterm/` (whichever exist; Claude's is created if neither does) | the agterm skill: control model, addressing, every `agtermctl` command |

It refuses to overwrite a directory whose `SKILL.md` lacks the `<!-- agterm-skill -->` marker, so a
skill of your own with that name is safe. The same skill ships as a Claude plugin
(`claude plugin install agterm@agterm`) — install by one route, never both. **Undo:** delete the
directory.

## 5. Settings ▸ Agents

**Found on This Mac** lists the CLIs AGX has a profile for and can see on `PATH` (plus
`~/.local/bin`, `~/.bun/bin`, the Homebrew prefixes — the GUI's own `PATH` has none of them). Connect
the ones you use; Rescan after installing one; Add Custom Agent… takes any name and shell line.
A connected agent is a *name* the rest of the app refers to: workspace defaults, `agx spawn --agent`,
scheduled sessions, failover.

## 6. A workspace per project

⌘⇧N, name it after the repo, then right-click the row ▸ Workspace Defaults…: the directory and the
agent. From now on ⌘N (or `session+`) in that workspace opens the agent in that directory, and a
Claude row gets `agx context` as its first turn through the `SessionStart` hook.

## 7. The first spawn

From any pane:

```sh
agx spawn --brief "Read docs/guide/README.md and list three things you would fix" \
          --name "Guide review" --foreground
```

A row appears, the agent starts with the brief as its first message, and within a few seconds the
row shows a blinking `●`. If the agent has never trusted that directory, its own trust dialog comes
first — accept it once, the brief runs right after (`--json` reports `cwd_trusted`).

**Try it:** close that session with ⌘W, then ⌘Z within 3 s — it is back, same conversation. Quit
AGX with ⌘Q and relaunch: the row is back and the agent never noticed.

## What is reversible

| step | reverses with |
|---|---|
| everything in 2–4 | the **Undo** lines above; nothing else on disk is touched |
| connected agents, workspace defaults | Settings ▸ Agents, the workspace's context menu |
| the app's own state | `~/Library/Application Support/agx/` (settings, windows, journal, durable servers) — quit first, then move it aside for a factory reset |
