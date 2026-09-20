# Gemini CLI & Antigravity — agent profile for AGX

Research date: 2026-09-11. Installed and inspected on this Mac; auth was NOT configured (no
GEMINI_API_KEY set), so live prompt execution wasn't tested — flags/behavior below are from
`--help` output of the real installed binary plus official docs (docs vs. binary occasionally
disagree; binary `--help` is treated as ground truth where they conflict).

## 1. Binary & version

- Install command that worked: `/opt/homebrew/bin/bun add -g @google/gemini-cli` (the path in the
  task brief, `~/.bun/bin/bun`, did not exist on this machine — bun itself lives at
  `/opt/homebrew/bin/bun`; `npm i -g @google/gemini-cli` is the documented fallback).
  Global bin installed to `/Users/rus/.bun/bin/gemini` — needs
  `export PATH="/Users/rus/.bun/bin:$PATH"`.
- `gemini --version` → `0.59.0`.
- Package: `@google/gemini-cli` on npm.

## 2. Seed first message

`gemini` distinguishes three modes via flags:

- **Headless (one-shot, no TUI):** `-p, --prompt <text>` — "Run in non-interactive (headless) mode
  with the given prompt. Appended to input on stdin (if any)." Exits after the reply. This is NOT
  what AGX wants for a pane (no ongoing TUI).
- **Interactive with a seeded first message (what AGX wants):**
  `-i, --prompt-interactive <text>` — "Execute the provided prompt and continue in interactive
  mode." This flag is present in `gemini --help` on the installed 0.59.0 binary but is undocumented
  in `docs/cli/headless.md` on GitHub main (docs appear stale relative to the shipped binary) —
  trust the `--help` output.
- **Bare positional:** `gemini [query..]` also launches interactive mode with that query as the
  initial prompt ("Launch Gemini CLI" is the default command; positional `query` = "Initial
  prompt. Runs in interactive mode by default; use -p/--prompt for non-interactive"). Functionally
  overlaps with `-i`; `-i` is the more explicit/documented-in-help form to use.

## 3. Resume

- `-r, --resume <id>` — "Resume a previous session. Use `latest` for most recent or index number
  (e.g. `--resume 5`)." Also accepts a full session UUID per `docs/cli/session-management.md`.
- `--list-sessions` — lists sessions for the current project (date, message count, first prompt)
  and exits.
- `--delete-session <index|id>` — removes a session.
- `--session-id <uuid>` — start a NEW session with a manually supplied UUID (useful if AGX wants
  to pre-assign an id before launch, e.g. to correlate with a pane).
- `--session-file <path>` — load a session from an explicit JSON file path (bypasses the
  id/project-hash lookup).
- **On-disk location:** `~/.gemini/tmp/<project_hash>/chats/` (project_hash derived from the
  project root path) — per `docs/cli/session-management.md`. Session id is a UUID.
- Checkpointing (separate feature, off by default) stores conversational/tool-call JSON at
  `~/.gemini/tmp/<project_hash>/checkpoints` and file snapshots in a shadow git repo at
  `~/.gemini/history/<project_hash>` — used for `/restore` (file revert), NOT for session resume.
- Confirmed by direct run: in JSON output mode (`-o json`) the CLI prints a `session_id` field
  even on an auth-error exit (`{"session_id": "...", "error": {...}}`) — so the id is obtainable
  from the process's own stdout without touching disk, which a wrapping hook/launcher could capture.
- Not independently verified: exact JSON schema of a chat session file (couldn't run with real
  auth) — treat `docs/cli/session-management.md`'s field list ("token usage statistics, prompts,
  responses, and tool executions") as approximate until a real file is inspected.

## 4. Hooks / lifecycle events

Yes — hooks exist as a first-class feature in 0.59.0, closely mirroring Claude Code's hook system
(there's literally a `gemini hooks migrate` subcommand: "Migrate hooks from Claude Code to Gemini
CLI").

- **Config:** `settings.json` `"hooks"` key, at any of three scopes: project
  (`.gemini/settings.json`), user (`~/.gemini/settings.json`), system
  (`/etc/gemini-cli/settings.json`). Confirmed live on this machine — the user's own
  `~/.gemini/settings.json` already has a working `hooks.BeforeTool` entry:
  ```json
  "hooks": { "BeforeTool": [ { "matcher": "google_search|read_file|grep_search",
    "hooks": [ { "type": "command", "command": "echo '...' >&2" } ] } ] }
  ```
- **Shape per event array:**
  ```json
  { "hooks": { "<EventName>": [ { "matcher": "regex|exact_string", "sequential": false,
    "hooks": [ { "type": "command", "command": "...", "name": "...", "timeout": 60000 } ] } ] } }
  ```
- **Event names:** `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent`, `BeforeModel`,
  `AfterModel`, `BeforeToolSelection`, `BeforeTool`, `AfterTool`, `PreCompress`, `Notification`.
  There is **no `Stop` event** (unlike Claude Code) — `AfterAgent`/`SessionEnd` are the closest
  analogues.
- **stdin JSON given to every hook** (base fields + per-event additions):
  ```json
  { "session_id": "...", "transcript_path": "...", "cwd": "...", "hook_event_name": "...",
    "timestamp": "..." }
  ```
  - `SessionStart` adds `"source": "startup"|"resume"|"clear"`.
  - `BeforeAgent`/`AfterAgent` add `"prompt"`, and `AfterAgent` also adds `"prompt_response"`,
    `"stop_hook_active"`.
  - `BeforeTool`/`AfterTool` add `"tool_name"`, `"tool_input"`, `"mcp_context"`,
    `"original_request_name"` (`AfterTool` also `"tool_response"`).
  - `Notification` adds `"notification_type": "ToolPermission"` (at least), `"message"`,
    `"details"`.
- **stdout JSON a hook can return:** `systemMessage`, `suppressOutput`, `continue`, `stopReason`,
  `decision: "allow"|"deny"|"block"`, `reason`, and `hookSpecificOutput` containing
  `additionalContext` (string — confirms context injection is supported, at least from
  `SessionStart`/`BeforeAgent`/`AfterTool` per the hooks index doc), `tailToolCallRequest`,
  `clearContext`, `llm_request`/`llm_response`, `toolConfig`. **Constraint: a hook must print
  nothing but the final JSON object to stdout** — all logging must go to stderr, or the JSON
  parse breaks (this is stated explicitly in the docs, worth enforcing in any AGX-side hook script).
- **"Waiting for user" detection — this is the useful one for AGX:** the `Notification` event
  fires exactly when "the model is waiting for user input or tool approval" (action-required case)
  and also on successful session completion. This is the closest Gemini-CLI analogue to Claude
  Code's permission/idle signal AGX needs for pane status. Separately/redundantly, the CLI also
  emits an **OSC 9 terminal notification escape sequence** (supported by iTerm2, WezTerm, Ghostty,
  Kitty) on the same conditions, falling back to a bell (BEL) — so AGX could in principle detect
  idle either via the hook OR by intercepting OSC 9 in the pane's PTY output, without any hook
  config at all.

## 5. Trust / first-run gates

- **Folder Trust** gate: on first run in a new folder, interactive mode shows a dialog offering
  trust-this-folder / trust-parent-and-subfolders / mark-untrusted, and lists what it found
  (commands, MCP servers, hooks, skills, setting overrides) before you decide.
- **In headless/non-interactive contexts this is a hard blocker, not a prompt**: an untrusted
  folder raises `FatalUntrustedWorkspaceError` and the process exits — this WILL break a seeded
  `-i`/`-p` launch from AGX on a first-run project unless bypassed.
- **Bypass for automation:** `--skip-trust` CLI flag ("Trust the current workspace for this
  session.") or env var `GEMINI_CLI_TRUST_WORKSPACE=true`. AGX should pass one of these on
  first-launch-per-project rather than let the gate fire in a pane with no way to answer a dialog.
- **Trust decisions storage:** `~/.gemini/trustedFolders.json` (path overridable via
  `GEMINI_CLI_TRUSTED_FOLDERS_PATH`).
- **Auth gate (separate from trust):** confirmed live — with no `GEMINI_API_KEY` /
  `GOOGLE_GENAI_USE_VERTEXAI` / `GOOGLE_GENAI_USE_GCA` set, every invocation (including `-p`/`-o
  json`) immediately errors with `"Please set an Auth method in your ~/.gemini/settings.json or
  specify one of the following environment variables..."` — headless mode does NOT fall back to an
  interactive OAuth browser flow; it just fails. Interactive mode with no cached credential and no
  env var is documented to prompt Google Sign-In (browser OAuth) instead. For AGX to seed a prompt
  non-interactively/reliably it needs a pre-existing cached credential or `GEMINI_API_KEY` in env.

## 6. Config paths

- User settings: `~/.gemini/settings.json`.
- Project/workspace settings: `<project>/.gemini/settings.json` (overrides user settings).
- System settings: `/etc/gemini-cli/settings.json` (per hooks docs; lowest precedence tier
  mentioned alongside project/user).
- Project-level instructions file: `<project>/GEMINI.md` / `~/.gemini/GEMINI.md` (analogue of
  Claude's CLAUDE.md — confirmed present on this machine at `~/.gemini/GEMINI.md`, currently just
  a `codebase-memory-mcp` usage-priority block).
- Trust store: `~/.gemini/trustedFolders.json` (env override `GEMINI_CLI_TRUSTED_FOLDERS_PATH`).
- Session data: `~/.gemini/tmp/<project_hash>/chats/`.
- Checkpoint data: `~/.gemini/tmp/<project_hash>/checkpoints` + shadow git repo
  `~/.gemini/history/<project_hash>`.
- Key env vars seen: `GEMINI_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`,
  `GOOGLE_API_KEY`, `GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_PROJECT`(`_ID`),
  `GOOGLE_CLOUD_LOCATION`, `GEMINI_CLI_TRUST_WORKSPACE`, `GEMINI_CLI_TRUSTED_FOLDERS_PATH`.

## 7. Usage / limits

- No dedicated `gemini usage`/quota subcommand was found in `--help` (top-level commands are only
  `mcp`, `extensions`, `skills`, `hooks`, `gemma`, and the default `[query..]` launcher — no
  `usage`/`quota`/`billing` command).
- `-o json` / `-o stream-json` output includes a `stats` object with token-usage metrics per
  response (confirmed shape includes `response`/`stats`/optional `error` for plain `json`; for
  `stream-json`, a final `result` event carries "aggregated stats"). This is the closest thing to
  a programmatic usage signal — AGX would have to parse it per-turn rather than query a global
  quota endpoint.
- Not found: any on-disk file or CLI surface exposing account-level quota/rate-limit remaining.
  **Gap** — flag for the parent task if usage/quota surfacing is a requirement.

## 8. Antigravity verdict

**No standalone terminal-agent CLI.** `~/.gemini/antigravity/bin/agentapi` is an **IDE-internal
RPC client**, not an independent agent process AGX could spawn and drive like `claude`/`gemini`.
Evidence: running it with no arguments prints its own subcommand list
(`get-conversation-metadata <conversation_id>`, `new-conversation [--model=...] <prompt>`,
`send-message <recipient_id> <content>`) but every invocation — including `--version` — immediately
fails with `{"error": "ANTIGRAVITY_LS_ADDRESS is not set"}`. That env var name ("LS" = language
server) indicates `agentapi` is a thin client that talks over some local address to a **running
Antigravity IDE process** (the actual agent brain lives inside the Electron/VS-Code-fork IDE, not
in this binary), matching the sibling directories on disk (`~/.gemini/antigravity-ide`,
`~/.gemini/antigravity-backup`). There is no discoverable way to start that language-server
process headlessly from the CLI side alone in the time available — it would require reverse
engineering the IDE's own bootstrap, which is out of scope here. **Conclusion: Antigravity cannot
be integrated into AGX as a pane agent the way `claude`/`gemini` are; it's an IDE feature, not a
CLI.** (Per task instructions, nothing about Antigravity was configured or modified — inspection
only.)

## 9. Gaps

- **Not tested live** (no auth configured in this sandbox, by design — task said not to launch the
  interactive TUI and adding a real `GEMINI_API_KEY` was out of scope): actual `-i` seeded-prompt
  behavior end-to-end, actual `--resume latest` round-trip, actual on-disk session JSON schema,
  actual `Notification` hook firing in practice, actual OSC 9 sequence bytes emitted. Everything in
  §2-4 above is from `--help` (binary ground truth) + docs (may be stale, as demonstrated by
  `-i/--prompt-interactive` being undocumented in `headless.md` despite existing in `--help`) — a
  follow-up with a real API key should re-verify before AGX ships an adapter.
  - **No `Stop` event.** AGX's existing hook vocabulary (built for Claude Code) assumes
  `Stop`/`SessionStart` naming; Gemini's closest equivalents are `AfterAgent`/`SessionEnd` —
  any shared hook-dispatch code in AGX needs a name-mapping layer, not a shared literal event name.
- **No usage/quota API** (§7) — if AGX's pane chrome shows quota bars per-agent (as it likely does
  for Claude via `turn.end.context.tokens`), Gemini CLI has no equivalent global signal; only
  per-turn token stats via `-o json`/`stream-json`, which means AGX would have to accumulate them
  itself rather than ask the CLI directly.
- **Folder-trust + auth are two separate blocking gates** or a first launch — an AGX adapter must
  handle both (`--skip-trust` or `GEMINI_CLI_TRUST_WORKSPACE=true`, plus a pre-existing cached
  credential or `GEMINI_API_KEY`) or a seeded pane will just print an error and exit instead of
  opening the TUI.
- **Antigravity is a dead end for AGX** (§8) — don't spend further effort trying to shell out to it.
