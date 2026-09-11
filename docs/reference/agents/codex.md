# Codex CLI — ground truth for AGX integration

_Researched 2026-09-11. Binary: `~/.local/bin/codex` → `codex-cli 0.154.0` (this machine's install is
the ChatGPT-Desktop-bundled build, `CODEX_CLI_PATH` in `~/.codex/config.toml` points at
`/Applications/ChatGPT.app/Contents/Resources/codex`; a plain OSS install would have a leaner
config.toml but the same CLI surface). Interactive TUI was never launched during this research._

## 1. Binary & version / what AGX already does

- `codex --version` → `codex-cli 0.154.0`.
- **Status hook** — `agterm/Resources/agent-status/agterm-codex-status.sh` (installed to
  `~/.config/agx/agent-status/agterm-codex-status.sh`). Dispatches on `$1` (`session-start`,
  `user-prompt-submit`, `pre-tool-use`, `post-tool-use`, `permission-request`, `stop`,
  `__watch-blocked`) and reports through `agterm-agent-status.sh` → `agtermctl session status`.
  Because Codex fires `PermissionRequest` *before* Auto Review decides, the hook doesn't trust that
  event alone — it starts a background watcher (`start_watcher`/`watch_for_blocker`) that polls the
  pane's visible footer text (`agtermctl session text`) for prompt strings ("press enter to
  confirm", "allow command?") and only then reports `blocked`; it self-clears back to `active` if
  the prompt disappears. `stop` reads `last_assistant_message` from hook stdin (via
  `plutil -extract last_assistant_message raw -o - -`) and reports `blocked` if it contains `?`,
  else `completed --auto-reset`.
- **Hook registration table** — `AgentHooksInstall.swift:78-85`, `codexHooks`: `SessionStart`→
  `session-start`, `UserPromptSubmit`→`user-prompt-submit`, `PreToolUse`→`pre-tool-use`,
  `PostToolUse`→`post-tool-use`, `PermissionRequest`→`permission-request`, `Stop`→`stop`. The
  installer writes these as inline `[[hooks.<Event>]]` TOML tables into `~/.codex/config.toml`
  inside a managed `# >>> agterm agent-status >>>` / `# <<< agterm agent-status <<<` block (see
  `refreshManagedCodexBlock`, `AgentHooksInstall.swift:257-288`), and preserves any `[hooks.state...]`
  trust-hash entries Codex itself appends inside that block (Codex writes those at the *end* of
  config.toml, landing inside the managed block — the installer keeps that suffix on refresh).
- **Trust probe** — `scripts/agx:_codex_trusts` (line 274) reads `~/.codex/config.toml` and regex-matches
  `[projects."<realpath>"]` … `trust_level = "trusted"`. Dispatched from `_agent_trusts` (line 294) when
  the agent executable basename is `codex`. Returns `None` (no warning) if the file can't be read or
  the project has no entry (distinct from a confirmed `false`).
- Live example from this machine's `~/.codex/config.toml`: `[projects."/Users/rus/mmee"]` →
  `trust_level = "trusted"`, alongside 5 other trusted paths — confirms the probed shape is exactly
  what real config produces.

## 2. Seed first message

- `codex [OPTIONS] [PROMPT]` — confirmed: `codex "prompt"` is a first-class seed. Per `--help`:
  *"Optional user prompt to start the session"* — no subcommand needed, the interactive TUI opens
  with that prompt pre-submitted.
- Flags relevant to AGX pass-through (all present on the top-level `codex` command, and mirrored on
  `resume`/`exec`):
  - `-m, --model <MODEL>` — model override.
  - `-s, --sandbox <read-only|workspace-write|danger-full-access>` — sandbox policy for
    model-run shell commands.
  - `-C, --cd <DIR>` — working root (equivalent to Claude's implicit cwd-from-spawn-dir; explicit
    here, so AGX should pass the pane's cwd through `-C` rather than relying on process cwd if it
    ever spawns via a different mechanism).
  - `-a, --ask-for-approval <on-request|never>` — approval policy.
  - `--approve-for-me` — routes approvals through automatic review under `workspace-write` sandbox;
    this is the flag Auto Review-style automation should pass.
  - `--dangerously-bypass-approvals-and-sandbox` — full bypass, "EXTREMELY DANGEROUS... environments
    that are externally sandboxed" — only for a fully externally-sandboxed context (e.g. a
    disposable VM), not a general AGX default.
  - `--dangerously-bypass-hook-trust` — skips the hook-review gate (§5); relevant if AGX ever needs
    to spawn Codex non-interactively before a human has trusted the agterm-installed hooks.
  - `-p, --profile <NAME>` — layers `$CODEX_HOME/<name>.config.toml` on top of base config.
  - `-i, --image <FILE>...` — attach image(s) to the initial prompt.
  - `--worktree` — run in a new managed git worktree.
  - `--add-dir <DIR>` — extra writable dirs alongside the primary workspace.
  - `-c, --config <key=value>` — one-off TOML override, dotted path, e.g. `-c model="o3"`.

## 3. Resume

- `codex resume [SESSION_ID] [PROMPT] [--last] [--all] [--include-non-interactive]` — confirmed.
  `--last` "Continue the most recent session without showing the picker" is the direct analogue of
  Claude's `--resume <id>`/pin pattern; omitting `SESSION_ID` and `--last` opens a picker UI (must
  avoid in headless/pinned automation).
  Note: unlike `claude --resume <id>`, Codex's positional `SESSION_ID` also accepts "session name"
  (not just a UUID) — "UUIDs take precedence if it parses."
- **Session ids are real UUIDv7s and Codex tracks them in three places** on disk:
  - `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` — one rollout file per session;
    first line is a `session_meta` event whose `payload` includes `session_id`, `cwd`,
    `originator` (`codex_exec` for a headless `exec` run, etc.), `source` (`"exec"`/interactive),
    `thread_source`, `model_provider`, `cli_version`, and the base system prompt text. Measured
    directly: `head -1` of a real rollout file on this machine returned exactly this shape.
  - `~/.codex/session_index.jsonl` — flat index, one line per session: `{"id": "<uuid>",
    "thread_name": "<auto-generated title>", "updated_at": "<ISO8601>"}`. This is what backs the
    `codex resume` picker and is the cheapest place for tooling to enumerate sessions/titles without
    parsing full rollouts.
  - `~/.codex/thread_history_1.sqlite` (9.5MB on this machine) — the paginated thread-history store
    `codex migrate-rollouts` references; newer Codex versions are moving off flat-file rollouts
    toward this DB, so don't hard-code the `.jsonl` layout as permanent.
- **Hook stdin DOES carry the session id**, confirmed from official docs (`session_id` field, see
  §4) — this is exactly the mechanism `agterm`'s existing Claude-Code integration uses (bundled
  `~/.codex/skills/agterm/examples.md:45-66` even documents the analogous Claude Code
  `SessionStart` pattern verbatim: read `session_id` from hook stdin JSON, no env var equivalent,
  then write it into agterm's per-pane `session restore` pin so the *next* launch reattaches
  instead of forking). The same pattern is directly portable to Codex's `SessionStart` hook: on
  `source == "resume"` or on every `session-start`, a hook could shell out
  `agtermctl session restore "codex resume $(session_id) --last" --pane-id "$AGTERM_PANE_ID"` (or
  similar) so a relaunch reattaches to the live thread instead of starting fresh. **This is not yet
  wired** — the installed `agterm-codex-status.sh` only reports status glyphs, it never touches
  `session restore`. See §8.
- `codex fork`/`codex exec fork`/`codex exec resume` exist too — fork makes a *new* session id from
  a prior one (non-idempotent across restarts, same caveat the agterm docs call out for Claude's
  `--fork-session`).

## 4. Hooks

Full event list in this Codex version (`0.154.0`, confirmed via official docs fetch,
`learn.chatgpt.com/codex/hooks` — the canonical URL `developers.openai.com/codex/config-advanced`
308-redirects there):

`SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`,
`PostCompact`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`, `Interrupt`. AGX only
installs 6 of these (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PermissionRequest`, `Stop`) — `SessionEnd`/`PreCompact`/`PostCompact`/`SubagentStart`/
`SubagentStop`/`Interrupt` are unused.

**Standard stdin fields on every hook** (quoted from docs):
```json
{
  "session_id": "string",
  "transcript_path": "string | null",
  "cwd": "string",
  "hook_event_name": "string",
  "model": "string",
  "permission_mode": "string"
}
```
Turn-scoped hooks additionally carry `turn_id`; docs note *"Current Codex session id. Subagent
hooks use the parent session id"* — i.e. a subagent's hooks still report the top-level session id,
not a separate child id.

**Per-event extra fields** (confirmed via targeted doc fetch):
- `SessionStart`: `source` — one of `startup`, `resume`, `clear`, `compact`. No separate
  `thread_id` — `session_id` is the sole identifier.
- `PermissionRequest`: `turn_id`, `tool_name` (canonical name, e.g. `Bash`, `apply_patch`, or an MCP
  tool name), `tool_input` (tool-specific JSON), `tool_input.description` (optional). Fires "when
  Codex is about to ask for approval, such as a shell escalation or managed-network approval" —
  this is exactly why the AGX hook cannot trust it alone (see §1): it fires whether or not Auto
  Review will approve it silently.
- `Stop`: `turn_id`, `stop_hook_active` (bool), **`last_assistant_message`** (string|null,
  "Latest assistant message text, if available"). This confirms the field the installed
  `agterm-codex-status.sh` hard-codes (`plutil -extract last_assistant_message`) is a real,
  documented field — not a guess.

**Output contract** — a hook can return JSON on stdout to inject context or control flow:
```json
{
  "continue": true,
  "stopReason": "optional",
  "systemMessage": "optional",
  "suppressOutput": false,
  "hookSpecificOutput": { "additionalContext": "string" }
}
```
Docs: *"Plain text on stdout is added as extra developer context"* for `SessionStart` and
`UserPromptSubmit` specifically — i.e. those two events support the lightweight plain-text form (no
JSON envelope needed) the same way Claude Code's hooks do; other events require the JSON envelope.
`Stop` specifically: *"expects JSON on stdout when it exits 0. Plain text output is invalid for this
event."* This is the mechanism a future `agx context`-style injector would use for Codex: a
`UserPromptSubmit` hook emitting plain text (or `hookSpecificOutput.additionalContext`) is the
direct analogue of Claude Code's context-injection hook.

**Timeouts**: default 600s; `SessionEnd`/`Interrupt` default 1s (max 3s) — these two are meant to
be near-instant cleanup, not long-running.

**Matcher/config shape** (inline TOML, same style AGX already writes):
```toml
[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 script.py"
timeout = 30
statusMessage = "Checking command"
```
AGX's installed hooks omit `matcher` (fire unconditionally) and `statusMessage`.

Hooks can also load from `hooks.json` files (`~/.codex/hooks.json` or `<repo>/.codex/hooks.json`)
instead of inline `[hooks]` TOML tables — AGX currently only writes inline TOML.

## 5. Trust / first-run gates

- **Project trust** — `[projects."<abs-path>"] trust_level = "trusted"` in `~/.codex/config.toml`.
  Set the first time a user accepts Codex's one-time per-directory trust dialog. AGX's
  `_codex_trusts` (scripts/agx:274-289) reads this directly; a seeded brief "waits behind it exactly
  like Claude's" per the function's own docstring.
- **Hook review gate** — separate from project trust. Docs, quoted: *"Before a non-managed hook can
  run, Codex requires you to review and trust the exact hook definition. Codex records trust against
  the hook's current hash, so new or changed hooks are marked for review and skipped until
  trusted."* Managed via the in-TUI `/hooks` command. This is exactly the mechanism visible in this
  machine's live config as `[hooks.state."/Users/rus/.codex/config.toml:pre_tool_use:0:0"]` →
  `trusted_hash = "sha256:…"` entries (one per installed hook event) inside the agterm managed
  block — six such entries present, one per `codexHooks` row, confirming all six AGX-installed hooks
  have already been reviewed/trusted on this machine.
- `--dangerously-bypass-hook-trust` (top-level flag, §2) skips this gate for automation that already
  vets its hook sources — relevant if AGX ever needs a headless `codex exec` to run before a human
  has interactively trusted the hooks (a first-run scripted flow).
- **Login**: `codex login status` → `Logged in using ChatGPT` on this machine; `codex doctor --json`
  → `auth.credentials` check reports `"auth file": "~/.codex/auth.json"`, `"stored auth mode":
  "chatgpt"`. `codex login --with-api-key` / `--with-access-token` (stdin) / `--device-auth` are the
  non-interactive alternatives — relevant if AGX ever needs to detect "not logged in" before
  spawning a pane (analogous to a Claude Code first-run auth check).

## 6. Config paths / env

- `$CODEX_HOME` (default `~/.codex`) — confirmed via `codex doctor`: setting
  `CODEX_HOME=/tmp/nonexist` produces `"failed to resolve CODEX_HOME"` and doctor's `config.load`
  check fails outright, i.e. Codex fully keys its state root off this env var, same role as
  Claude Code's `CLAUDE_CONFIG_DIR`.
- Config file: `$CODEX_HOME/config.toml` (this install: `-rw-------` 5.1K, last modified today by
  the desktop app). AGX writes/reads the `[projects."<path>"]`, `[[hooks.<Event>]]`, and
  `[hooks.state."<key>"]` (trust-hash) sections; **read-only for this research task** per
  instructions, and correctly so — it's hand-edited by both Codex itself and the ChatGPT desktop
  app (plugin/marketplace tables, `[desktop]` UI prefs, `notify` array) and any external rewrite
  risks clobbering unrelated state.
- `-c, --config <key=value>` / `-p, --profile <name>` (→ `$CODEX_HOME/<name>.config.toml` layered on
  top) are the two supported override mechanisms — AGX could use `-c` for one-off per-spawn
  overrides instead of touching config.toml at all.
- Other `$CODEX_HOME` contents observed (for context, not to be relied on as stable API):
  `auth.json`, `sessions/` (rollout `.jsonl`), `session_index.jsonl`, `thread_history_1.sqlite`,
  `queue_1.sqlite` (backs `codex queue`), `state_5.sqlite`, `logs_2.sqlite`, `AGENTS.md` (user-level
  agent instructions, distinct from project `AGENTS.md`), `skills/`, `plugins/`. Several are
  `.sqlite`+`-wal`/`-shm` triples — actively written by a live daemon, not just per-invocation state.

## 7. Usage / limits

No plain-file or CLI-flag usage surface (no `codex usage`, no flat file AGX could `cat`). The real
surface is the **app-server JSON-RPC protocol** (`codex app-server`, stdio or
`codex app-server proxy` to the daemon's control socket; `codex app-server daemon start|restart|
stop|version` manages a persistent local daemon). Confirmed by dumping the protocol's JSON Schema
(`codex app-server generate-json-schema --out <dir>`):

- **`account/rateLimits/read`** → `RateLimitSnapshot`: `primary`/`secondary`
  `RateLimitWindow` (`usedPercent: int32`, `resetsAt: int64|null`, `windowDurationMins: int64|null`),
  `limitId`, `limitName`, `planType` (enum: `free|go|plus|pro|prolite|team|business|enterprise|…`),
  `rateLimitReachedType` (enum incl. `rate_limit_reached`, `workspace_owner_credits_depleted`,
  `workspace_member_usage_limit_reached`, …), `credits` (`CreditsSnapshot`: `balance: string|null`,
  `hasCredits: bool`, `unlimited: bool`), `individualLimit` (`SpendControlLimitSnapshot`: `limit`,
  `used`, `remainingPercent`, `resetsAt`). There's also a push notification,
  `AccountRateLimitsUpdatedNotification`, described as a *"Sparse rolling rate-limit update... merge
  available values into the most recent `account/rateLimits/read` response."*
- **`account/usage/read`** (params type `GetAccountTokenUsageParams`) →
  `GetAccountTokenUsageResponse`: `summary` (`AccountTokenUsageSummary`: `lifetimeTokens`,
  `peakDailyTokens`, `currentStreakDays`, `longestStreakDays`, `longestRunningTurnSec`),
  `dailyUsageBuckets` (array of `{startDate, tokens}`), and optional `threadUsage` (per-thread
  `ThreadUsage`: `threadId`, `estimatedUsageCreditsMicros`, `estimatedUsageUsdMicros`, `groups[]` of
  `ThreadUsageBreakdownGroup` — `model`, `reasoningEffort`, `speed`, `inputTokens`,
  `cachedInputTokens`, `netNewInputTokens`, `outputTokens`, `totalTokens`,
  `estimatedUsageCreditsMicros` — i.e. broken out per model/reasoning-effort/speed combination used
  in that thread).
- This is a real, structured surface `agx usage` (Claude-only today) could target for Codex, but it
  requires speaking JSON-RPC to a running/spawnable app-server rather than reading a file — a
  materially different integration shape than whatever Claude-side file/command `agx usage` reads
  today (not inspected in this task; worth diffing before building).
- No TUI `/status`-equivalent output was captured (interactive TUI was not launched, per task
  constraints) — the schema above is the only measured evidence of what such a view would show.

## 8. Gaps vs the Claude integration

1. **No resume-pin on relaunch.** Claude Code's side (per `agterm/examples.md:45-66`, cited in §3)
   uses a `SessionStart` hook to rewrite `agtermctl session restore` with the live session id every
   start, so an agterm window relaunch reattaches instead of forking a new session. Codex's
   `SessionStart` hook carries the same ingredient (`session_id` in stdin JSON, `source` field to
   distinguish `startup`/`resume`/`clear`/`compact`) — **this is directly doable with the existing
   hook contract**, just not implemented: `agterm-codex-status.sh`'s `session-start` case only calls
   `stop_watcher` + `report_status idle`, it never touches `session restore`. Building it means
   parsing hook stdin JSON for `session_id` (the script currently never reads its own stdin) and
   shelling `agtermctl session restore "codex resume <id> --last" --pane-id "$AGTERM_PANE_ID"`.
2. **No `agx context` equivalent.** Claude Code has some form of context injection (not itself
   inspected in this task) — Codex's `UserPromptSubmit` hook plain-text-stdout / `SessionStart`
   `hookSpecificOutput.additionalContext` (§4) is the same shaped door, again **not wired**, just
   available.
3. **No `agx usage` for Codex.** Doable, but architecturally different: Claude's is presumably a
   file/log read; Codex requires driving `codex app-server` JSON-RPC (`account/rateLimits/read`,
   `account/usage/read`, §7) — either a one-shot `codex app-server proxy` round-trip or reading from
   an already-running daemon (`codex app-server daemon start`/`version`). Non-trivial but the schema
   is fully specified.
4. **`PermissionRequest` false-positive workaround is Codex-specific and already handled** — not a
   gap, just noting AGX's footer-watcher (§1) is a real workaround for a real Codex ordering quirk
   (`PermissionRequest` fires before Auto Review decides), with no equivalent complexity on the
   Claude side mentioned in the source files read for this task.
5. **Session enumeration** — no gap: `~/.codex/session_index.jsonl` (id + thread_name + updated_at)
   is a cheap, already-there source for a resume-picker UI in AGX, cheaper than parsing rollout
   `.jsonl` files or the sqlite thread-history store.
