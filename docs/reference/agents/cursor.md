# Cursor CLI (`cursor-agent`) — ground truth for AGX integration

Researched 2026-09-11 by installing the real binary and reading `--help` + official docs
(cursor.com/docs/cli/*). Facts below are measured, not guessed. Not logged in during this
research (no Cursor account credentials used) — auth-gated behavior is reported from the actual
error messages the CLI produces, not assumed.

## 1. Binary & version

- **Install command (the only supported path):** `curl https://cursor.com/install -fsS | bash`
  Downloads `agent-cli-package.tar.gz` from `downloads.cursor.com`, unpacks into
  `~/.local/share/cursor-agent/versions/<version>/`, symlinks `~/.local/bin/cursor-agent` and
  `~/.local/bin/agent` → `.../versions/<version>/cursor-agent`.
- **Installed version (this run):** `2026.09.10-fd3934a` (`cursor-agent --version` /
  `cursor-agent -v`).
- **Binary is a bash launcher**, not a raw executable: `~/.local/share/cursor-agent/versions/<v>/cursor-agent`
  is a `#!/usr/bin/env bash` script that sets `CURSOR_INVOKED_AS="$(basename "$0")"`, resolves
  `NODE_BIN="$SCRIPT_DIR/node"` (a bundled Node), sets `NODE_COMPILE_CACHE` to
  `~/Library/Caches/cursor-compile-cache` on macOS, then execs the bundled `index.js` (chunked,
  minified — `18.index.js`, `190.index.js`, … alongside `better_sqlite3.node`, `cursor-askpass`,
  `cursorsandbox`, `crepectl`).
- **⚠️ Name collision on this machine**: the shell alias `agent` is already bound to
  `ssh worker -t "tmux attach -t agent || tmux new -s agent"` (Fred remote tmux). AGX must invoke
  the CLI as **`cursor-agent`**, never the bare `agent` symlink, to avoid ambiguity for humans
  reading transcripts (the symlink itself works fine if PATH-resolved directly, this is a human/
  alias-collision risk, not a technical one).
- `~/.cursor/` already existed from the Cursor IDE before this install (per task brief) — the
  installer did not touch `~/.cursor/cli-config.json` or `~/.cursor/mcp.json`, it only added
  `~/.local/share/cursor-agent/` and the two `~/.local/bin` symlinks.

## 2. Seed first message (interactive with initial prompt)

- **Positional argument, not a flag**: `cursor-agent "refactor the auth module to use JWT tokens"`.
  From `--help`: `Usage: agent [options] [command] [prompt...]` — `prompt` is a plain positional
  arg described as "Initial prompt for the agent". This starts the **interactive** TUI with that
  prompt already submitted.
- This is distinct from **headless/print mode**, which is a separate flag: `-p, --print` ("Print
  responses to console (for scripts or non-interactive use). Has access to all tools, including
  write and shell."). `-p` changes execution mode; it does not change how the prompt is passed —
  the prompt is still the trailing positional arg: `cursor-agent -p "find and fix perf issues" --model gpt-5`.
- `--output-format <text|json|stream-json>` only applies with `-p`. `--stream-partial-output` only
  applies with `-p --output-format stream-json`.
- **Measured**: without auth, both interactive-seeded (`cursor-agent "hello there" </dev/null`)
  and print-mode (`cursor-agent -p "say hi" --output-format json`) fail identically and instantly:
  ```
  Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY environment variable.
  ```
  No TUI was drawn, no shell/tool call was attempted — the auth check happens before any prompt
  processing in both modes. Confirms it's safe to shell out `cursor-agent "<prompt>"` from a host
  app without login and get a clean, parseable failure rather than a hang or garbage TTY state.

## 3. Resume

- Flags on the base command: `--resume [chatId]` ("Select a session to resume") and `--continue`
  ("Continue previous session").
- Subcommands: `cursor-agent ls` ("Resume a chat session" — **interactive picker**), `cursor-agent
  resume` ("Resume the latest chat session"), `cursor-agent create-chat` ("Create a new empty chat
  and return its ID").
- **Measured, unauthenticated:**
  - `cursor-agent resume` → `No previous chats found.` (clean text, no hang, no auth error — so
    `resume` at least partially works pre-login, reading local state only).
  - `cursor-agent ls` → **crashes**, not a clean picker, when stdin isn't a TTY:
    ```
    ERROR Raw mode is not supported on the current process.stdin, which Ink uses as input stream by default.
    ```
    `ls` is an Ink (React-for-CLI) fullscreen picker — it **requires a real TTY** and cannot be
    driven headlessly or piped. AGX must never call `cursor-agent ls` from a non-PTY context; if
    AGX gives the pane a real PTY this would presumably render fine, but it was not verified here
    (would require a real login + an interactive session, out of scope for this research pass).
  - `cursor-agent create-chat` → returned a bare UUID (e.g. `6d1fb8e1-1541-44ce-b2a4-9351b7d3a668`)
    with exit 0 and **no auth error**, even fully logged out. This is the one command confirmed to
    work fully offline/unauthenticated — useful if AGX wants to pre-allocate a chat id before a
    user logs in, but note: the returned id did **not** show up under `~/.cursor/projects/` or
    anywhere else on disk that a `grep -rl <uuid>` could find (see below) — it may be an in-memory
    placeholder, or storage may require the process to fully initialize state first. Not fully
    resolved — see Gaps.
- **Where session ids live on disk**: not conclusively located. `~/.cursor/projects/Users-rus-mmee/`
  exists (auto-created, path-derived project key, slashes→dashes) but was empty after the
  `create-chat` call above. Minified source (`index.sqlite`, `better_sqlite3.node`,
  `src/persistence/persistent-session.ts`, `src/state/session.ts`) confirms sessions are persisted
  via a bundled SQLite (`better-sqlite3`), and there's an internal "agent-store-sync" module with
  file-lock semantics (`tryAcquireStoreLock`, `AgentStoreSyncSessionController`) suggesting
  multi-window/multi-process session sharing — but the exact `.sqlite` file path was not found by
  static string search within the time budget. **A hook script cannot be shown here to reliably
  read the current session id off disk from this research alone** — the one thing a hook script
  *can* rely on is the `session_id` field present in every `stream-json` event (see §4) and the
  `--resume [chatId]` flag taking that same id back in.
- `cursor-agent persist` (see below) is a *different* concept: server/background sessions that
  survive terminal/SSH disconnect, not the same as chat-history resume.

## 4. Hooks / lifecycle events

Config file search order confirmed both from `--help`-adjacent docs and directly from strings in
the shipped `190.index.js` (`configDirKey:"project"`, `"Project hooks.json"`,
`configDirKey:"user"`, `"User hooks.json"`, `configDirKey:"enterprise"`, `"Enterprise hooks.json"`,
`configDirKey:"team"`):

| Level | Path |
|---|---|
| Enterprise (MDM) | macOS: `/Library/Application Support/Cursor/hooks.json`; Linux/WSL: `/etc/cursor/hooks.json`; Windows: `C:\ProgramData\Cursor\hooks.json` |
| Team | distributed via Cursor dashboard (cloud) |
| Project | `<project-root>/.cursor/hooks.json` — script paths resolve as `.cursor/hooks/script.sh` |
| User | `~/.cursor/hooks.json` — script paths resolve relative to `~/.cursor/` |

Priority: Enterprise > Team > Project > User (per docs.cursor.com/docs/hooks).

**Event names** (confirmed via docs + present as literal strings in the shipped code):
`sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, `postToolUseFailure`, `subagentStart`,
`subagentStop`, `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`,
`afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`, `preCompact`, `stop`,
`afterAgentResponse`, `afterAgentThought` (agent/chat hooks) plus Tab-specific
`beforeTabFileRead`/`afterTabFileEdit`, and app-lifecycle `workspaceOpen` (fires outside any agent
session, no `conversation_id`).

**Common stdin JSON shape for every hook invocation** (per docs.cursor.com/docs/hooks):
```json
{
  "conversation_id": "string",
  "generation_id": "string",
  "model": "string",
  "model_id": "string",
  "model_params": [{ "id": "string", "value": "string" }],
  "hook_event_name": "string",
  "cursor_version": "string",
  "workspace_roots": ["<path>"],
  "user_email": "string | null",
  "transcript_path": "string | null"
}
```
So **yes**, hooks do carry `conversation_id` (plus a per-generation `generation_id`) — this is the
mechanism AGX would use to correlate a hook firing with a specific pane/session, not a separate
"session id" field. `workspaceOpen` is the one event that omits `conversation_id`/`generation_id`/
`model`/`transcript_path`.

**Blocking / context injection**: a command-based hook writes JSON to stdout:
```json
{ "permission": "allow" | "deny" | "ask", "user_message": "<shown in client>", "agent_message": "<sent to agent>", "updated_input": {} }
```
Exit code 0 = use the JSON output; exit code 2 = block (same as `permission: "deny"`); any other
exit code = hook failed, **fails open** (action proceeds) unless the hook definition sets
`"failClosed": true`. `updated_input` lets a hook rewrite the tool call before it runs, and
`agent_message` lets a hook inject text back into the agent's context — so yes, a hook can inject
context, not just allow/deny.

**"Waiting for approval" signal**: there is **no dedicated event** for this. `permission: "ask"`
returned from `beforeShellExecution`/`beforeMCPExecution` is how a hook *requests* interactive
confirmation, but the CLI doesn't fire a distinct lifecycle event AGX could listen for that says
"I am now blocked waiting on a human." AGX would need to infer this from process state (e.g. a
`tool_call` `started` event in stream-json with no matching `completed` event yet, combined with
the process not exiting — see §7's stream-json note) rather than from hooks.

**CLI vs IDE**: hooks apply to CLI-driven agent/cloud-agent sessions too, not just the IDE, but
**not all events fire in cloud/headless execution**. Cloud-agent-supported set: `beforeShellExecution`,
`afterShellExecution`, `beforeReadFile`, `afterFileEdit`, `preToolUse`, `postToolUse`,
`postToolUseFailure`, `subagentStart`, `subagentStop`, `beforeSubmitPrompt`, `preCompact`,
`afterAgentResponse`, `afterAgentThought`, `stop`. **Not** available in cloud/headless:
`sessionStart`, `sessionEnd`, `beforeMCPExecution`, `afterMCPExecution`, `beforeTabFileRead`,
`afterTabFileEdit`, `workspaceOpen` (IDE-only or timing-constrained). This was not independently
re-verified against the local interactive CLI in this pass (would need a real login) — reported as
documented, not measured.

## 5. Trust / first-run gates

- **Auth is the hard gate, and it blocks before anything else.** Every invocation attempted here
  without `CURSOR_API_KEY` set and without a prior `cursor-agent login` failed immediately with:
  `Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY environment variable.`
  This happened uniformly for a seeded interactive prompt, `-p` print mode, and (per `--help`) is
  presumably true for `resume`/most subcommands too — `create-chat` was the one exception observed
  (see §3).
- **`cursor-agent login`** — "Authenticate with Cursor. Set `NO_OPEN_BROWSER` to disable browser
  opening." Not run in this research (would create a real logged-in session tied to a Cursor
  account, out of scope / explicitly told not to touch `~/.cursor/*` config). Docs describe it as
  opening the default browser for an OAuth-style flow; exact token storage location not verified
  first-hand, docs only say "credentials are securely stored locally." The bundled binary ships a
  `cursor-askpass` helper and an env var `AGENT_CLI_CREDENTIAL_STORE=file` that changes credential
  storage behavior (skips a "system CA" / presumably OS-keychain path when set to `file`) —
  strongly suggests the **default** credential store is the OS keychain, with a file-based fallback
  for headless/server boxes. Not independently confirmed by inspecting the keychain.
- **`--api-key <key>` / `CURSOR_API_KEY` env var** is the non-interactive alternative to `login` —
  confirmed working syntax from `--help`: `agent --api-key <key> "prompt"` or `export CURSOR_API_KEY=...`.
  This is the path AGX should use for a fully headless/seeded pane (no browser OAuth dance).
- **No separate "workspace trust" prompt was observed** blocking a seeded prompt pre-login — the
  auth error preempts everything, so trust-prompt behavior for an *authenticated* session was not
  exercised in this pass. `--trust` flag exists ("Trust the current workspace without prompting")
  implying such a prompt exists post-login for new workspace roots, and `-w/--worktree` implies a
  related first-touch setup (`.cursor/worktrees.json` setup scripts, skippable via
  `--skip-worktree-setup`) — both documented, neither measured live.
- `cursor-agent about` and `cursor-agent status`/`whoami` both work fine unauthenticated and are a
  safe way for AGX to probe login state without triggering any gate:
  ```
  $ cursor-agent status
  Not logged in
  $ cursor-agent about
  CLI Version         2026.09.10-fd3934a
  User Email          Not logged in
  ```

## 6. Config paths

- `~/.cursor/cli-config.json` — global CLI settings (pre-existed from the IDE on this machine).
  Measured real content includes: `permissions.allow`/`permissions.deny` (e.g. `"Shell(ls)"`),
  `approvalMode: "allowlist"`, `sandbox: {mode:"disabled", networkAccess:"user_config_with_defaults"}`,
  `attribution.attributeCommitsToAgent`/`attributePRsToAgent`, editor/display prefs. **Not modified
  in this research.**
- `~/.cursor/mcp.json` — global MCP server config (pre-existed, not modified). Project-level
  equivalent: `<project>/.cursor/mcp.json`.
- Per docs: permissions/allow-deny lists live in `~/.cursor/cli-config.json` (global) and
  `<project>/.cursor/cli.json` (project-level), with syntax `Shell(cmd)`, `Read(glob)`,
  `Write(glob)`, `WebFetch(domain)`, `Mcp(server:tool)`; `deny` takes precedence over `allow`.
- `~/.cursor/hooks.json` (user-level hooks) and `<project>/.cursor/hooks.json` (project-level) —
  see §4.
- `~/.cursor/projects/<Sanitized-Cwd-Path>/` — auto-created per-project state dir (confirmed:
  `~/.cursor/projects/Users-rus-mmee/` was created just from running `cursor-agent` inside
  `~/mmee`; slashes in the cwd become dashes). Was empty in this run.
- `~/.cursor/statsig-cache.json` — telemetry/feature-flag cache (pre-existing, untouched).
- `~/.cursor/worktrees/<reponame>/<name>/` — target of `-w/--worktree`.
- **Install location**: `~/.local/share/cursor-agent/versions/<version>/` (versioned, supports
  side-by-side upgrades); `~/.local/bin/{cursor-agent,agent}` symlinks point at the current version.
- **Node compile cache**: `~/Library/Caches/cursor-compile-cache` (macOS) — safe to delete, perf-only.
- **Env vars confirmed** (from `--help` + binary launcher script + strings):
  `CURSOR_API_KEY`, `CURSOR_API_ENDPOINT` (default `https://api2.cursor.sh`), `NO_OPEN_BROWSER`
  (disables browser popup for `login`), `CURSOR_INVOKED_AS` (set by the launcher to
  `basename "$0"`, i.e. `cursor-agent` vs `agent` — could let a hook/script distinguish which
  symlink invoked it), `NODE_COMPILE_CACHE`, `AGENT_CLI_CREDENTIAL_STORE` (`file` = don't use
  OS-native credential store / skip system CA lookup — headless/server-friendly).

## 7. Usage / limits

- `cursor-agent about [--format text|json]` — version, OS, terminal, shell, model, **subscription
  tier** (`Unknown` when logged out), user email. This is the closest thing to a "plan info"
  surface, but tier detail is thin (just a tier name field, no quota numbers observed while logged
  out — could not verify what an authenticated `about --format json` returns).
- `cursor-agent status|whoami [--format text|json]` — auth status only.
- `cursor-agent models` / `--list-models` — lists available models for the account (not testable
  logged-out; would presumably need auth to enumerate a real model list vs. defaults).
- `cursor-agent bedrock` — subcommand to configure AWS Bedrock as a backing provider (BYO-cloud
  billing path noted for completeness, not explored).
- No dedicated "usage/quota" command was found in `--help` (no `cursor-agent usage` or similar).
  If AGX needs live quota/limit numbers it likely has to go through the Cursor dashboard/API, not
  the CLI — **gap**, see §8.
- `--output-format stream-json` (`-p` only) is the structured surface a host app should parse for
  turn-by-turn progress. Documented event shapes (docs.cursor.com/docs/cli/reference/output-format):
  `{"type":"system","subtype":"init", "session_id", "cwd", "model", "permissionMode", "apiKeySource"}`
  once at start; `{"type":"user", "message":{...}, "session_id"}`; `{"type":"assistant", "message":{...}, "session_id"}`
  per complete message (with optional `timestamp_ms`/`model_call_id` on pre-tool-call flushes to
  discard when using `--stream-partial-output`); `{"type":"tool_call","subtype":"started"|"completed","call_id","tool_call":{...},"session_id"}`;
  and a terminal `{"type":"result","subtype":"success","duration_ms","is_error":false,"result":"<full text>","session_id"}`.
  A host app determines "turn complete" from the `result` event and "tool running" from unmatched
  `tool_call started` vs `completed` `call_id` pairs. This was read from docs, not independently
  produced (needs an authenticated run) — treat the exact field list as documented-not-measured.

## 8. Gaps for AGX

- **Login flow is entirely unverified live** — no `cursor-agent login` was run (would create a
  real account session). AGX's onboarding for Cursor panes will need its own throwaway-account
  test pass to confirm the browser OAuth UX, `NO_OPEN_BROWSER` device-code fallback (if any), and
  exact token storage path before shipping a "log in from inside AGX" flow.
- **No confirmed on-disk path for chat/session history** — `create-chat` returns a UUID but it
  wasn't findable on disk afterward in this logged-out run; the real per-chat SQLite path
  (`index.sqlite` per strings) wasn't pinned down. AGX cannot currently build a "read the last N
  cursor-agent sessions from disk" feature the way it might for another agent with a plain JSONL
  transcript file — it would have to rely on `cursor-agent ls`/`resume`/`--resume <id>` as the only
  interface, and `ls` requires a real TTY (Ink), so AGX must give that specific invocation a proper
  pty, not just a piped subprocess.
- **No "waiting for approval" lifecycle event** — AGX has to infer a stalled/awaiting-approval pane
  from stream-json tool_call state (or from PTY output pattern-matching in interactive mode), not
  from a clean hook signal. This is a materially different integration shape than agents that emit
  an explicit approval-request event.
- **Hooks are Cursor's own mechanism, project- or user-scoped, and mutate `~/.cursor/hooks.json` or
  `<project>/.cursor/hooks.json`** — the task explicitly forbade touching `~/.cursor/*`, so no hook
  was actually installed/fired in this research; the schema above is docs+strings, not observed
  stdin/stdout from a live hook invocation. If AGX wants a session-id-bearing hook to phone home
  per pane, that's a **project-level `.cursor/hooks.json` file AGX would need to write into each
  workspace it opens** — a footprint AGX doesn't have with, e.g., a CLI that reads a pure env var
  or CLI flag for the same purpose.
- **No usage/quota CLI surface found** — can't show a Cursor pane's remaining budget the way AGX
  might for a provider with a `usage` subcommand; would need the web dashboard or an
  undocumented API.
- **`--sandbox`, `--auto-review`, `--approve-mcps` semantics were read from `--help` text only**,
  not exercised (all require an authenticated run to actually trigger a tool call to observe
  behavior). Treat their one-line descriptions in §... as authoritative-but-unexercised.
