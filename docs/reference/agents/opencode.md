# OpenCode — agent profile for AGX

Researched 2026-09-11. Binary: `~/.bun/bin/opencode`, version **1.17.13** (`opencode --version`).
Do not launch the interactive TUI or run `opencode auth`/`providers login` while researching —
all facts below come from `--help`, read-only `sqlite3` queries on the existing local DB, the
shipped agterm plugin source, and https://opencode.ai/docs (config/cli/permissions/providers
pages — no dedicated `/docs/sessions/` page exists on the site as of this date).

## 1. Binary & version

- Path: `~/.bun/bin/opencode` (bun-installed).
- `opencode --version` → `1.17.13`.
- Top-level command tree (`opencode --help`): `completion`, `acp`, `mcp`, `[project]` (default =
  start TUI), `attach <url>`, `run [message..]`, `debug`, `providers` (alias `auth`), `agent`,
  `upgrade`, `uninstall`, `serve`, `web`, `models`, `stats`, `export [sessionID]`, `import <file>`,
  `github`, `pr <number>`, `session`, `plugin <module>` (alias `plug`), `db`.

## 2. Seed first message — interactive TUI vs headless `run`

Two distinct paths, confirmed from `--help`:

- **Interactive TUI with a prompt already submitted**: `opencode [project] --prompt "<text>"`.
  Top-level flag `--prompt` = `"prompt to use"` (string). This starts the full TUI and feeds the
  prompt in (per opencode.ai/docs/cli — TUI accepts `--prompt` to seed the input interactively).
  Combine with `--agent <name>` and `-m/--model provider/model` to pin agent/model at seed time.
  There is also `--mini` (minimal interactive interface, boolean) and `-i/--interactive` (only
  documented under `run`, see below) as adjacent but different modes.
- **Headless, non-interactive**: `opencode run [message..]` — message is a positional array
  (`opencode run "do the thing"`), no TUI is drawn. Docs describe it as "run opencode in
  non-interactive mode by passing a prompt directly." Supports `--format json` for raw NDJSON-ish
  event output (`--format default|json`), `-f/--file` to attach files, `--title` to name the
  session, `--attach <url>` to target a running server, `--variant` (reasoning effort:
  high/max/minimal), `--thinking` (show thinking blocks), `-i/--interactive` ("run in direct
  interactive split-footer mode" — a lighter-weight embedded UI, NOT the full TUI), `--auto`
  (auto-approve permissions not explicitly denied — dangerous).
- For AGX panes that want the real Ghostty-style TUI (like the Claude Code integration), the
  seed mechanism is `opencode <project> --prompt "<seed>"`; for a fire-and-forget headless pane it
  is `opencode run --format json "<seed>"`.

## 3. Resume

- Flags (same shape on both top-level and `run`): `-c/--continue` ("continue the last session",
  boolean), `-s/--session <id>` ("session id to continue"), `--fork` ("fork the session when
  continuing" — requires `--continue` or `--session`).
- **Storage is SQLite, not per-session files**: `~/.local/share/opencode/opencode.db` (WAL mode,
  `opencode.db-wal`/`-shm` present). Confirmed tables include `session`, `session_message`,
  `session_input`, `session_context_epoch`, `session_diff`, `session_share`, `message`, `part`,
  `project`, `project_directory`, `credential`, `account`, `permission`, `todo`, `event`,
  `event_sequence`, `workspace`, `migration`.
- `session` table schema (read via `sqlite3 ... ".schema session"`) includes: `id` (format
  `ses_<hex>` e.g. `ses_0e04fd913ffeJbfDRSAEpCUMOA`), `project_id`, `workspace_id`, `parent_id`
  (sessions can be forked/nested), `slug`, `directory` (per-session cwd — this is almost certainly
  what scopes "last session" for `--continue`), `title`, `agent`, `model`, token/cost columns
  (`tokens_input/output/reasoning/cache_read/cache_write`, `cost`), `time_created`, `time_updated`,
  `time_compacting`, `time_archived`.
- `opencode session list` / `opencode session delete <sessionID>` exist as CLI subcommands; run
  from inside a project directory it lists that project's sessions (an out-of-project invocation
  in this research returned empty — scoping is per-project/`directory`, matching the `session`
  table's `directory` column).
- `opencode export [sessionID]` / `opencode import <file>` — dump/restore a session as JSON; useful
  for AGX to read a full transcript without touching the DB directly.
- **Can the plugin learn the current session id from events?** Yes — every plugin `event` payload
  carries `properties.sessionID` (used directly by the shipped agterm plugin, see §4). So on
  `session.created`/`session.status` the plugin already sees the session id live; AGX's status
  wrapper could be extended to also emit/persist that id for a "resume this pane" feature, but the
  current plugin does not persist it anywhere (see Gaps, §8).

## 4. Hooks / plugin events

- **Plugin loading**: auto-discovered from `~/.config/opencode/plugins/*.js` (global) or
  `.opencode/plugins/*.js` (project), no config entry required for these directories. Separately,
  `opencode.json`'s `"plugin"` array can name npm packages (`opencode plugin <module>` CLI installs
  those and updates config). `--pure` (top-level flag, boolean) disables **all external plugins**
  for that invocation — worth surfacing in AGX as "safe mode" since it silently kills the status
  plugin too.
- **Full event vocabulary** (from docs + confirmed against the shipped plugin's `switch`):
  `session.created`, `session.status` (busy/retry/idle — the modern event; `session.idle` is
  called out in the plugin as **deprecated**, still emitted, handled as a no-op to avoid double
  firing), `session.compacted`, `session.deleted`, `session.diff`, `session.error`,
  `session.updated`, `permission.asked`, `permission.replied`, `question.asked`,
  `question.replied`, `question.rejected`, `message.updated`/`message.removed`,
  `message.part.updated`/`removed`, `tool.execute.before`/`after`, `command.executed`,
  `file.edited`, `file.watcher.updated`, `installation.updated`, `lsp.client.diagnostics`,
  `lsp.updated`, `server.connected`, `todo.updated`, `shell.env`, `tui.prompt.append`,
  `tui.command.execute`, `tui.toast.show`, `experimental.session.compacting`.
- **Existing agterm plugin** (`agterm/Resources/agent-status/opencode/agterm-status.js`, installed
  to `~/.config/opencode/plugins/agterm-status.js` by `AgentHooksInstall.swift`) only implements a
  single `event` hook and only reacts to a subset:
  - `session.status` (busy/retry → ACTIVE; idle → COMPLETED/BLOCKED via a set-wide latch across all
    sessions sharing one OpenCode process/pane — comments in the file explain the busy/errored/
    overflow bookkeeping in detail).
  - `permission.asked` / `question.asked` → BLOCKED.
  - `permission.replied` / `question.replied` / `question.rejected` → ACTIVE.
  - `session.error` → BLOCKED, with special-casing: `MessageAbortedError`/`AbortError` (user hit
    Esc) is swallowed entirely (no state change, relies on the next idle's auto-reset completed);
    `ContextOverflowError` is deferred — its real meaning (auto-compaction resumed vs turn ended)
    is only known from the *next* event (busy vs idle).
  - Everything else (`tool.execute.*`, `message.*`, `file.*`, `command.executed`, `todo.updated`,
    `tui.*`, `experimental.session.compacting`) is **ignored** — mapped to `null`/`default: null`.
  - Gate: plugin no-ops entirely if `process.env.AGTERM_SESSION_ID` is unset (so it's inert outside
    agterm panes). Reports go through a serialized queue to
    `$AGTERM_STATUS_WRAPPER` (default `~/.config/agterm/agent-status/agterm-agent-status.sh`),
    spawned detached with a 10s hard-kill timeout so a stuck wrapper can't wedge OpenCode's event
    loop.
- **Install mechanism** (`AgtermStatusHooksInstall.swift`, constants only — actual install function
  not shown in this excerpt but inferable from the constants): copies the bundled
  `opencode/agterm-status.js` to `~/.config/opencode/plugins/agterm-status.js`. No `opencode.json`
  edit needed since the plugins dir is auto-discovered. Ownership/overwrite guarded by a marker
  string `// agterm-opencode-status-plugin` at the top of the file — `mayOverwriteOpenCodePlugin`
  only allows overwrite if that marker is already present (so it won't clobber a user's own
  same-named plugin).
- **Can a plugin inject context/system prompt at session start?** No — confirmed via docs: no
  `session.created`-time prompt/context injection hook exists. The only context-injection surface
  is `experimental.session.compacting`, which can supply `output.prompt`/`output.context` to the
  *compaction* prompt only, not the initial system prompt or first user turn.
- **Is `permission.asked` a reliable "blocked" signal?** For permission/question prompts, yes — the
  plugin already treats it as ground truth and it is a first-class, non-deprecated event pair
  (asked/replied). It does NOT cover every way a session can look "stuck" — e.g. it doesn't cover
  `tui.toast.show` prompts or interactive `/connect` provider-auth prompts (see §5), so AGX's
  "blocked" state is only as complete as OpenCode's permission system, not a full UI-blocking
  detector.

## 5. Trust / first-run gates

- Provider auth is managed via `opencode providers` (alias `opencode auth`): `providers list`
  (`ls`), `providers login [url]`, `providers logout [provider]`. `opencode models [provider]`
  lists available models.
- Auth flow per docs: first launch with zero configured providers surfaces an in-TUI `/connect`
  command (interactive: pick provider → paste API key or OAuth). This is **not** a hard blocking
  gate before the TUI even starts — the docs describe it as prompting when a model needs to be
  selected, not preventing launch.
- **Non-interactive bypass for AGX**: set provider env vars before spawning (`ANTHROPIC_API_KEY`,
  `AWS_PROFILE`/`AWS_REGION` for Bedrock, `NVIDIA_API_KEY`, etc.) or pre-populate
  `opencode.json` with `"apiKey": "{env:VAR}"` references. If a provider is already configured
  (credentials exist), a seeded `--prompt`/`run` should proceed without any first-run interactive
  gate.
- **Credential storage in this install is SQLite, not a JSON file**: despite docs describing
  `~/.local/share/opencode/auth.json`, on this machine (v1.17.13) there is no `auth.json` on disk
  at all — instead the DB has `credential`, `account`, `control_account`, `account_state` tables
  (`credential` schema: `id, integration_id, label, value, connector_id, method_id, active,
  time_created, time_updated`; currently 0 rows here — no provider configured on this box). Docs
  are stale on this point for the installed version; AGX should not assume a discoverable
  `auth.json` file to check "is a provider configured" — would need `opencode providers list` or a
  DB read instead.
- `--auto` flag (top-level and `run`): auto-approves permissions "that are not explicitly denied"
  — explicitly marked "(dangerous!)" in `--help`. Relevant if AGX ever wants a fully unattended
  headless mode.

## 6. Config paths

From `opencode debug paths`:
```
home       /Users/rus
data       /Users/rus/.local/share/opencode
bin        /Users/rus/.cache/opencode/bin
log        /Users/rus/.local/share/opencode/log
repos      /Users/rus/.local/share/opencode/repos
cache      /Users/rus/.cache/opencode
config     /Users/rus/.config/opencode
state      /Users/rus/.local/state/opencode
tmp        /var/folders/.../T/opencode
```
- Global config: `~/.config/opencode/opencode.json` (or `.jsonc` — this machine has an essentially
  empty `opencode.jsonc` with just `"$schema": "https://opencode.ai/config.json"`).
- Config precedence (docs, merged not replaced, later overrides on conflicting keys only): remote
  `.well-known/opencode` → global `~/.config/opencode/opencode.json` → `OPENCODE_CONFIG` env path →
  project `opencode.json` → managed/MDM settings (highest).
- Env vars: `OPENCODE_CONFIG` (custom config file path), `OPENCODE_CONFIG_DIR` (custom dir for
  agents/commands/modes/**plugins**), `OPENCODE_MODEL` (usable inside config via
  `{env:OPENCODE_MODEL}` templating), `OPENCODE_TUI_CONFIG`, plus standard provider credential env
  vars (`ANTHROPIC_API_KEY`, `AWS_REGION`, `AWS_PROFILE`, etc.).
- Plugin dirs: global `~/.config/opencode/plugins/`, project `.opencode/plugins/` (this is where
  agterm's status plugin lives — see §4). `opencode.json`'s `"plugin"` array is a third,
  npm-package-based loading path (`opencode plugin <module>` / `plug` installs+registers it).
- `--pure` disables external plugins for one invocation (see §4).
- Data: SQLite DB at `~/.local/share/opencode/opencode.db` (+ `-wal`/`-shm`), logs at
  `~/.local/share/opencode/log/opencode.log`, `repos/` subdir under data.

## 7. Usage / limits

- `opencode stats` — "show token usage and cost statistics." Flags: `--days N` (default: all
  time), `--tools N` (top N tools, default all), `--models [N]` (hidden by default; pass a number
  for top N or bare flag for all), `--project <name>` (filter; default all projects, empty string
  = current project). This is the only exposed usage/cost surface via CLI.
- Per-session cost/token columns already live in the `session` SQLite table (`cost`,
  `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`,
  updated live as `time_updated` changes) — AGX could read these directly for a per-pane usage
  readout instead of shelling out to `opencode stats` each time, mirroring how mmee reads
  `turn.end.context.tokens` from the Claude adapter rather than recomputing from raw usage.
- No rate-limit/quota surface was found in `--help` output; that would live provider-side
  (Anthropic/OpenAI dashboards), not in OpenCode itself.

## 8. Gaps vs Claude integration — what AGX cannot do (yet) with OpenCode

- **No system-prompt/context injection at session start.** The Claude Code integration (per mmee's
  own `/chat` design, ADR-0015) can hand a persona/system-prompt to an isolated agent turn.
  OpenCode's plugin API has no equivalent hook — the only prompt-shaping surface is
  `experimental.session.compacting`, which only fires on compaction, not turn/session start. Any
  "persona" for OpenCode would have to be baked into the seed `--prompt` text itself, or into
  `opencode.json`'s agent config (`opencode agent create`/`opencode agent list` — agent *identity*
  and system prompt live in named agents, not injected per-session by a plugin).
- **No built-in "resume pin" analogous to Claude's session-id echo.** The plugin sees
  `properties.sessionID` on every event but does not persist or surface it back to AGX (no report
  call carries the session id — only status keywords `active/blocked/completed`). To let a user
  "resume this exact OpenCode pane later," AGX would need to extend the plugin to also write the
  session id (e.g. to a per-pane file or via an additional wrapper arg) so a later `opencode -s
  <id>` can target it precisely, instead of relying on the directory-scoped `--continue` heuristic
  (which only recovers "last session in this project directory," and is ambiguous if multiple
  OpenCode panes share a worktree).
- **`session.status`/`session.idle` overlap requires the plugin's own de-duplication logic**
  (documented in-file as "deprecated: OpenCode also emits session.status(type=idle); handling both
  would double-fire completed") — a real quirk of the event API, not an agterm design choice; any
  future direct integration must replicate that guard.
- **Multi-session-per-pane bookkeeping is heuristic, not authoritative.** The plugin's ACTIVE/
  BLOCKED/COMPLETED state is a *process-wide* union across every session that ever ran in one
  OpenCode instance (comment: "so the three Sets below track them together rather than per-
  session"). A subagent (`task` tool) spawning a nested session could, in edge cases, make the
  parent pane's status flicker if the heuristics' set-membership assumptions are violated by a new
  OpenCode release changing event ordering.
- **`permission.asked` doesn't cover every UI-blocking situation.** First-run `/connect` provider
  auth and `tui.toast.show` prompts are not wired to BLOCKED — a pane could visually be waiting on
  the user (e.g., "pick a provider") while agterm still reports COMPLETED/ACTIVE.
  because those events are either unhandled or not emitted for that flow.
- **No usage/limit event stream** — `opencode stats`/session token columns are pull-only (poll or
  query SQLite); there's no push event like `session.status` for cost/usage updates, so a live
  token/cost readout in AGX would need polling, not an event hook.
- **Auth-state discovery is undocumented for this version.** Docs describe a JSON `auth.json` that
  doesn't exist in 1.17.13 — actual credentials are in SQLite (`credential`/`account` tables,
  schema in §5). AGX code that wants to check "is OpenCode already authenticated" should shell out
  to `opencode providers list` rather than assume a file path from the docs.
- **`--pure` silently disables the status plugin** with no separate AGX-visible signal — if a user
  (or a future AGX flag) passes `--pure`, the pane will simply stop reporting status with no error,
  which could look like a hang rather than an intentional opt-out.
