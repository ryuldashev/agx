# Personal-layer inventory: agx/agterm references outside the app

Read-only inventory. Question: what is "the AGX experience" that lives OUTSIDE `agx.app` on
Ruslan's machine, and would a fresh install of agx NOT bring to another user by itself?

Bottom line up front: two layers exist.
1. **Installer-writable layer** — `~/.claude/settings.json` hook entries, `~/.claude/skills/agterm/`,
   `~/.codex/config.toml` hook block, `~/.config/agx/agent-status/*` — all written by
   `Help ▸ Install` (AgentHooksInstaller / agent-status installer). Any user who runs the installer
   gets these verbatim. **Product already ships this via installer — nothing new to build**, just
   confirm the installer covers what's below.
2. **Genuinely personal layer** — hand-written prose rules in `~/CLAUDE.md` / `~/.claude/CLAUDE.md`
   (habits, permissions, workflow conventions), Ruslan's own `keymap.conf` custom commands, amem
   lessons-learned notes, and `~/Library/Application Support/agx/settings.json` (his one connected
   agent + prefs). This is what would NOT reach a new user and is candidate onboarding material.

## ~/CLAUDE.md and ~/.claude/CLAUDE.md — verbatim agx/agterm mentions

| item | what it does | verbatim key text | classification |
|---|---|---|---|
| `~/CLAUDE.md:49-52` | Auto commit+deploy policy for agterm repo work | "agx (`~/agterm`) — коммит и деплой БЕЗ подтверждения ... Гейты зелёные → сразу `git commit` своих файлов + `make deploy`. Единственное, что остаётся ему — перезапуск приложения (`agtermctl app relaunch` кладёт все живые сессии, включая мою)." | **personal** — a maintainer's own workflow trust level for HIS repo, not something agx as a product prescribes |
| `~/CLAUDE.md:54-57` | Redefines "close the session" as an agx-specific action | "«Закрой сессию» / «заверши сессию» / «закрывай» ... = закрыть ЭТУ вкладку в AGX, а не хендофф ... (2) `agtermctl session close --target "$AGTERM_SESSION_ID"` (свою, не `active`). Если сессия — не в AGX (`AGTERM_ENABLED` пуст) — просто завершить работу." | **personal harness rule**, see dedicated section below — this is a vocabulary mapping only Ruslan's Claude knows |
| `~/CLAUDE.md:58` | Pre-authorizes `agx spawn`/`agtermctl` without asking, explains why | "`agx spawn` / `agtermctl` — штатный инструмент Руслана ... Спавнить сессии — его главная фича, делать без вопросов. Правила `Bash(agx:*)` и `Bash(agtermctl:*)` добавлены в `~/.claude/settings.json` 2026-09-06 после того, как auto-классификатор трижды заблокировал `agx spawn`." | **personal permission grant** + workaround note for a classifier false-positive |
| `~/.claude/CLAUDE.md:122-123` | Notes Codex is a full agent inside AGX | "В AGX Codex — полноправный агент: `agx spawn --agent codex --brief "..." --name "..." --cwd <dir>` ... Статус-хуки agterm для Codex уже в `config.toml`." | personal note / product-should-ship (multi-agent support is a real agx feature, this is just Ruslan recording it works) |
| `~/.claude/CLAUDE.md:216` | Cross-reference to a separate mmee doc | "`~/mmee/docs/reference/agterm-forkability.md` (паттерны качества agterm для skills-ядра)." | personal (unrelated side-project referencing agx as a quality example) |

## ~/.claude/settings.json

### hooks (every entry mentioning agx/agterm)

| event | matcher | command | what it does | classification |
|---|---|---|---|---|
| SessionStart | (none) | `[ -n "$AGTERM_ENABLED" ] || exit 0; ... agtermctl session restore "zsh -lc 'exec claude --resume $sid --fork-session'" --target "$AGTERM_SESSION_ID" ...` | Restores a Claude conversation into the same agx tab after app/session restart, using AGTERM_* env | **installer-writable** (agent-status / restore feature) |
| SessionStart | (none) | `$HOME/.claude/hooks/agx-session-context.sh` | Injects `agx context` JSON (UI self-description: sidebar state, workspace, etc.) into Claude's context, only when `AGTERM_ENABLED=1` | installer-writable (this specific hook file lives under `~/.claude/hooks/`, mirrored copy also under `~/.config/agx/agent-status/agx-session-context.sh`) |
| SessionStart | (none) | `'/Users/rus/.config/agx/agent-status/agx-session-restore.sh' --resume-line 'claude --resume {id} --fork-session'` | Same restore mechanism, agent-status installer's own copy | installer-writable |
| SessionStart | (none) | `'/Users/rus/.config/agx/agent-status/agx-session-context.sh' --format claude` | Same context-injection, agent-status installer's own copy | installer-writable |
| UserPromptSubmit | (none) | `'/Users/rus/.config/agx/agent-status/agterm-agent-status.sh' active --blink` | Sets the tab's status pill to "active" + blinks it in the sidebar | installer-writable |
| PostToolUse | (none) | `'/Users/rus/.config/agx/agent-status/agterm-agent-status.sh' active --blink` | Same, refires after each tool call | installer-writable |
| Stop | (none) | `'/Users/rus/.config/agx/agent-status/agterm-agent-status.sh' completed --auto-reset` | Marks tab status "completed", auto-resets after a timeout | installer-writable |
| StopFailure | (none) | `'/Users/rus/.config/agx/agent-status/agx-agent-failure.sh'` | Marks tab status as failed | installer-writable |
| Notification | `permission_prompt` | `'/Users/rus/.config/agx/agent-status/agterm-agent-status.sh' blocked` | Marks tab status "blocked" when Claude asks for permission | installer-writable |

Non-agx hooks present (for completeness, NOT agx-related): `screenshot-guard.sh` (PreToolUse on
chrome-devtools screenshot), `session-end-review.sh` / macmon optimize / sessionize.py (SessionEnd),
`subagent-stop-learn.sh` (SubagentStop). These are pure personal-workflow hooks, unrelated to agx.

### permissions.allow entries mentioning agx

- `Bash(agx:*)` and `Bash(agtermctl:*)` — added 2026-09-06 per the CLAUDE.md note above, to stop the
  auto-mode classifier from blocking `agx spawn`. **Personal permission grant**, but the underlying
  problem (classifier flags `agx spawn`) is a product-facing rough edge worth a "product should ship"
  fix (e.g. an allow-by-default recommendation in onboarding docs, or the CLI signaling intent).

### env vars

None of the `env` block's 16 keys (`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `CLAUDE_CODE_SUBAGENT_MODEL`,
etc.) reference agx/agterm/AGTERM_* — that block is unrelated Claude Code tuning, not agx-specific.

## ~/.claude/hooks/*

| file | agx-related? | what it does |
|---|---|---|
| `agx-session-context.sh` | **yes** | SessionStart hook; gated on `AGTERM_ENABLED=1`; calls `~/.local/bin/agx context`, wraps result as `hookSpecificOutput.additionalContext` JSON so Claude knows the current agx UI state (sidebar/workspace/tab) |
| `.rtk-hook.sha256` | no | unrelated rtk (token-killer) integrity hash |
| `context-nudge.sh` | no | context/compaction reminder |
| `rtk-rewrite.sh` | no | rtk read-only command rewriting |
| `screenshot-guard.sh` | no | screenshot token-budget nudge |
| `session-end-review.sh` | no | reminds to update `.claude/agents/*.md` Learned sections |
| `subagent-stop-learn.sh` | no | SubagentStop lesson-capture nudge |

Only one of the six hook files under `~/.claude/hooks/` is agx-specific; the rest are installer-writable
copies under `~/.config/agx/agent-status/` (see settings.json table above) plus pure personal-workflow
hooks unrelated to agx.

## ~/.claude/skills/

Skills present (21 dirs): agents-best-practices, **agterm**, animation-vocabulary, anti-slop,
behavior-coach, design-squad, edu-forge, emil-design-eng, icon-forge, impeccable, lesson-forge,
luma-icons, method-squad, poster-forge, product-squad, review-animations, skill-conductor, startupit,
taste-skill. Only `agterm/` is agx-related; no other skill's SKILL.md mentions agx/agterm.

`~/.claude/skills/agterm/SKILL.md` frontmatter (36KB file total, plus `reference.md` 82KB,
`examples.md` 44KB, `troubleshooting.md` 15KB, `scripts/`):

- `name: agterm`
- `description`: drive agterm via `agtermctl` CLI + local control socket — sessions, workspaces,
  panes, scratch terminal, overlays, native fuzzy picker, inline image display, typing/copy/search,
  notifications, window management, font size, keymap/config reload, event subscription, filing
  GitHub issues/discussions.
- `when_to_use`: long trigger-phrase list (`agterm`, `agtermctl`, `session.new`, `AGTERM_SESSION_ID`,
  `AGTERM_SOCKET`, "drive or script agterm", "troubleshoot agterm", etc.)
- `allowed-tools: Bash(agtermctl *)`

This skill is generic/reusable — it documents the public `agtermctl` control API, not Ruslan's
personal setup. **Product-should-ship / already does** (it's the "bundled `plugins/agterm/skills/agterm/`"
that CLAUDE.md's Cross-surface contracts section says installers copy from).

## ~/.config/agterm/* and ~/.config/agx/*

Note: `~/.config/agterm` and `~/.config/agx` are the **same directory** (one is a symlink/alias to
the other — `ls -la` on both returned identical file listings/timestamps).

| file | what it does | classification |
|---|---|---|
| `keymap.conf` | Global keymap: built-in action chord reference (all commented/default) + **two custom personal commands**: `command "Студия" cmd+shift+s /bin/zsh $HOME/mmee/skills-core/studio-menu.sh` (native picker menu for Ruslan's mmee skills-core project) and `command "Скиллы — отчёт" ... agtermctl session overlay open "zsh -lc $HOME/mmee/skills-core/report-view.sh"` (overlay terminal report viewer) | **personal** — hardcoded paths into `~/mmee`, meaningless to another user |
| `ghostty.conf` | Sets `shell-integration-features = cursor,sudo,title` (drops `ssh-*` because agx ships no `ghostty` CLI so the shell-integration ssh wrapper would break) | **product-should-ship as default** — this is a correctness fix for agx's own packaging quirk (no `ghostty` binary at `Contents/MacOS`), not a personal preference; every agx user hits the same ssh-wrapper breakage without it |
| `restore-denylist.conf` | Programs not to re-run on "Restore running commands on restart" (`tmux`, `screen`, `zellij` by default, all commented) | ships as default template, unmodified by Ruslan — **product default**, not personal |
| `agent-status/` (dir) | Full agent-status installer payload: `agterm-agent-status.sh`, `agx-session-restore.sh`, `agx-session-context.sh`, `agx-agent-failure.sh`, `shell/integration.sh`+`.fish`, and per-agent `agents/<name>/agent.json` (droid, aider, gemini, mimo, copilot, cursor, claude, codex, qwen, pi, amp, crush, hermes, kimi, opencode, goose) plus `agents/codex/status.sh` and `agents/pi/extension.ts`, `agents/opencode/plugin.js` | **installer-writable** — this is the multi-agent status-integration bundle the Help▸Install installer drops for every supported CLI agent, identical for any user who installs |

## ~/.codex/config.toml and ~/.codex/AGENTS.md

- `~/.codex/config.toml` lines 105-158: marked block `# >>> agterm agent-status >>>` ... `# <<<` —
  installs the same 6 lifecycle hooks (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
  PermissionRequest, Stop) all calling `'/Users/rus/.config/agx/agent-status/agents/codex/status.sh' <event>`,
  plus a `[hooks.state]` block with `trusted_hash` entries (Codex's own hook-trust mechanism, one
  hash per hook path, all `sha256:...`). **Installer-writable**, identical across users who install
  Codex agent-status support.
- `~/.codex/AGENTS.md`: no agx/agterm mention at all — its content is entirely about
  `codebase-memory-mcp` (an unrelated MCP knowledge-graph tool). Confirmed via grep, zero hits.

## ~/Library/LaunchAgents/*.plist

Grepped every plist in `~/Library/LaunchAgents/` (case-insensitive) for `agx`/`agterm`: **zero
matches**. The only plist present is `com.rus.claude-archive.plist` (session-transcript archiver,
unrelated to agx — see `~/CLAUDE.md`'s "Архив транскриптов сессий" section). agx has **no LaunchAgent
of its own** on this machine; it is a foreground GUI app, not a background daemon.

## ~/amem store — agx-related lessons

`~/amem/mem search agx` surfaced (index at `~/amem/store/index.md:15-20`):

| file | summary |
|---|---|
| `team/agterm/agent-profiles.md` | AgentProfile catalog in `AgentCatalog.swift` + `scripts/agx` mirror; measured seed/resume/hooks/trust facts per supported CLI agent (updated 2026-09-11) |
| `team/agterm/reader-pane.md` | agx reader pane (`session.reader`) (2026-09-10) |
| `team/agterm/spawn-gotchas.md` | agterm/agx — session-spawn pitfalls (2026-09-02) |
| `team/agx/detach-layer.md` | agx's detach layer: vendored `abduco` (ISC, not dtach/GPLv2) so PTYs survive app quit; abduco has no scrollback replay buffer; `agtermApp.makeSurface`/`GhosttySurfaceView(command:)` is the integration point (2026-09-10) |
| `team/agx/gotchas.md` | Practical gotchas: fork provenance (`umputun/agterm` → `ryuldashev/agx`), `make deploy` staged-swap semantics, **never edit `~/Library/Application Support/agx/settings.json` live** (SettingsModel overwrites on quit), no session-id↔tab mapping without the hook, scratch-terminal cmd+j vs cmd+opt+j remap history, `journal.jsonl` action log, notarization requirements for release, Codex-as-agent verification (2026-08-27 → 2026-09-11) |
| `team/modme/lessons.md:36` | Auto-mode classifier blocked `agx spawn` 3x when brief implied a prod deploy → fixed via `Bash(agx:*)`/`Bash(agtermctl:*)` allow rules (2026-09-06) — this is the amem-side record of the same incident CLAUDE.md documents |

This is Ruslan's/agents' own engineering knowledge base about building agx — **not** end-user-facing;
it's development history, useful for onboarding a new *contributor*, not a new *user*.

## ~/Library/Application Support/agx/settings.json

Full contents (small file, reproduced verbatim since it's short):

```json
{
  "agents": [{"command": "claude", "id": "11111111-1111-1111-1111-111111111111", "name": "Claude Code"}],
  "inheritGlobalGhosttyConfig": true,
  "permissionsPrimerShown": true,
  "restoreRunningCommand": true,
  "splitPaneBackgroundFade": 85,
  "splitPaneBackgroundMirror": true,
  "welcomeShown": true
}
```

| field | value | classification |
|---|---|---|
| `agents` | one entry: `Claude Code` → command `claude`, fixed UUID `11111111-...` | **personal but shape is product-default** — only one agent registered despite CLAUDE.md describing Codex-as-agent usage elsewhere; either Codex was added via `agx spawn --agent codex` transiently (not persisted as a named connected agent) or this file predates that workflow. Worth checking with Ruslan / re-reading after a fresh `agx spawn --agent codex` |
| `inheritGlobalGhosttyConfig` | true | product default flag, a **setting**, not a hardcoded personal value |
| `permissionsPrimerShown` | true | onboarding flag — user has dismissed the permissions primer once |
| `restoreRunningCommand` | true | product default toggle |
| `splitPaneBackgroundFade` / `splitPaneBackgroundMirror` | 85 / true | cosmetic prefs, product settings |
| `welcomeShown` | true | onboarding flag — first-run welcome already dismissed |

Nothing here is exotic personal configuration beyond the one connected agent — it's exactly the shape
a fresh install's Settings UI would produce after clicking through onboarding once.

## Rules in personal CLAUDE.md that are really harness rules

These are prose instructions living in Ruslan's private `~/CLAUDE.md` that encode agx-specific
*meaning* Claude must know to behave correctly inside an agx session — none of this ships with the
app itself; it is entirely dependent on the running Claude Code instance having read this file.

> **agx (`~/agterm`) — коммит и деплой БЕЗ подтверждения** (Руслан, 2026-09-09: «чтобы я не ждал потом»).
> Гейты зелёные → сразу `git commit` своих файлов + `make deploy`. Единственное, что остаётся ему —
> перезапуск приложения (`agtermctl app relaunch` кладёт все живые сессии, включая мою). Если в дереве
> WIP другой сессии — коммитить только свои файлы, перед `make deploy` убедиться, что чужой xcodebuild
> не идёт (`pgrep -fl xcodebuild`), и сказать одной строкой, что деплой унёс чужой WIP.

> **«Закрой сессию» / «заверши сессию» / «закрывай» (2026-09-12) = закрыть ЭТУ вкладку в AGX**, а не
> хендофф и не «завершить разговор». Порядок: (1) дописать handoff/лог, если есть незакоммиченное — коммит
> своих файлов; (2) `agtermctl session close --target "$AGTERM_SESSION_ID"` (свою, не `active`).
> Если сессия — не в AGX (`AGTERM_ENABLED` пуст) — просто завершить работу. Не спрашивать «точно закрыть?».

> **`agx spawn` / `agtermctl` — штатный инструмент Руслана (его агентский терминал AGX).** Спавнить
> сессии — его главная фича, делать без вопросов. Правила `Bash(agx:*)` и `Bash(agtermctl:*)`
> добавлены в `~/.claude/settings.json` 2026-09-06 после того, как auto-классификатор трижды
> заблокировал `agx spawn` и Руслану пришлось запускать руками. Если снова блок — не переформулировать
> команду, а сразу сказать Руслану и дать ему строку с `!`.

Why these are "harness rules, not product rules": all three depend on Claude Code reading a private
`CLAUDE.md` that will never exist on another user's machine. A new agx user gets `AGTERM_ENABLED`,
`AGTERM_SESSION_ID`, the `agterm` skill (generic control-API docs), and the agent-status hooks — but
NOT the vocabulary mapping "закрой сессию = close this tab", NOT the blanket pre-authorization for
`agx spawn`/`agtermctl` (they'd hit the same auto-mode classifier block Ruslan hit on 2026-09-06 and
have no CLAUDE.md line telling them it's safe to pre-approve), and NOT the "commit+deploy without
asking" trust level for the agx repo itself (repo-specific, only relevant to contributors anyway).

**Product-facing takeaway for onboarding docs**: the `agterm` skill's `when_to_use` trigger list
already covers "close the session" mechanically (`session.close`), but nothing in the shipped skill
or docs tells a *fresh* Claude session that colloquial phrases like "закрой сессию" / "close this
session" map to `session.close --target $AGTERM_SESSION_ID` rather than ending the conversation. That
mapping, and the auto-mode-classifier friction on `agx spawn`, are the two concrete "personal layer"
items with real product value if surfaced in onboarding (e.g. a recommended CLAUDE.md snippet the
installer could suggest, or a permissions.allow recommendation).
