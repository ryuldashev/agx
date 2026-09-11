# Mimo Code — agent profile

Ground-truth research for AGX integration, measured against the locally installed binary
(`~/.bun/bin/mimo`, npm package `@mimo-ai/cli` v0.1.4) on 2026-09-11. No interactive TUI was
launched; no user config was modified. Facts below come from `--help` output, `mimo debug`
commands, and static analysis (`strings`) of the compiled Bun executable
(`@mimo-ai/mimocode-darwin-arm64/bin/mimo`, a bundled/minified JS blob — no readable TS source,
but it ships its own bundled markdown docs for its plugin API, extracted verbatim below).

## 1. Binary & version

- Installed via `npm install -g @mimo-ai/cli` (or Xiaomi's install script `curl -fsSL
  https://mimo.xiaomi.com/install | bash`). Wrapper at
  `~/.bun/install/global/node_modules/@mimo-ai/cli/bin/mimo` is a small Node launcher that
  resolves and `spawnSync`s the platform-specific binary from an `optionalDependencies` package
  (`@mimo-ai/mimocode-darwin-arm64` etc.) — actual binary:
  `~/.bun/install/global/node_modules/@mimo-ai/mimocode-darwin-arm64/bin/mimo` (Mach-O 64-bit
  arm64, 91MB, a Bun single-file-executable bundle).
- `mimo --version` → `0.1.4`.
- `MIMOCODE_BIN_PATH` env var overrides which binary the launcher runs (checked first, before
  platform detection).
- Repo: `https://github.com/XiaomiMiMo/MiMo-Code` (MIT license + separate `USE_RESTRICTIONS.md`).
  Website: `https://mimo.xiaomi.com/coder`. Product name in-app: "MiMoCode" / "mimocode".
- **Architecture note (important for integration):** this is very clearly a fork of
  **sst/opencode** — internal identifiers, default local URL (`http://opencode.internal`), an
  `opencode` auth-path helper (`~/.local/share/opencode/auth.json`, used for a GitLab OAuth
  credential path — legacy naming, not renamed), the whole HTTP/SSE server+client split, and the
  full REST route surface (`/session/{id}/...`) match opencode's design. Any opencode
  integration knowledge (client-server model, SSE event bus, ACP bridge) largely transfers.

## 2. Seed first message

Two distinct ways to start with an initial prompt, per `mimo --help`:

- **Interactive (TUI) with a seeded prompt** — the default command, `mimo [project] --prompt
  "<text>"`. Confirmed in the compiled source (`xY0` command handler for `$0 [project]`): the
  resolved prompt is computed by `eB2(A.prompt)`, which additionally reads `stdin` when it is not
  a TTY (`Bun.stdin.text()`) and **concatenates piped stdin content after the `--prompt` text**.
  The resulting string is passed as `args.prompt` into the TUI bootstrap (`OO({... args: {
  prompt: W, ... }})`). This opens the full interactive TUI with that prompt already loaded —
  this is the "seed and let it run interactively" path AGX wants for a pane.
  - Other seed-adjacent flags on this same default command: `-m/--model provider/model`,
    `--agent <name>`, `-c/--continue`, `-s/--session <id>` (+ `--fork`), `--never-ask` (auto-decide
    without asking, permissions excluded), `--trust` (skip workspace-trust prompt, see §5).
  - Not independently confirmed at runtime whether `--prompt` **auto-submits** the turn or merely
    pre-fills the input box awaiting Enter — the task explicitly forbade launching the TUI to
    check. Flagged as a gap; test in a disposable directory later.
- **Headless / one-shot ("print mode")** — `mimo run [message..]` (positional array, joined) or
  `mimo run --command <cmd>`. Runs one turn against a session and exits; not a persistent TUI.
  Key flags: `--format default|json` (json = raw JSON event stream on stdout — the machine-
  readable path for a headless AGX-driven turn), `-f/--file <path>` to attach files, `--title`,
  `--session`/`--continue`/`--fork` to target a session, `--dangerously-skip-permissions` (auto-
  approve everything not explicitly denied), `--share`, `--variant` (reasoning effort:
  high/max/minimal), `--thinking` (show thinking blocks), `--attach <url>` to run against an
  already-running `mimo serve`. This is the equivalent of Claude Code's `--print`/headless mode.

## 3. Resume

- `-c, --continue` — continue the last session (works on both the interactive default command and
  `mimo run`/`mimo attach`).
- `-s, --session <id>` — resume a specific session by id (session ids look like
  `ses_f6f45d626ffe...`, verified against real entries in this user's own DB).
- `--fork` — fork instead of continuing in-place; requires `--continue` or `--session` (validated:
  the CLI hard-errors "`--fork requires --continue or --session`" otherwise).
- `mimo session list` — lists sessions (id, title, updated time) from local storage. Ran once
  read-only; every real session shown was actually a **Claude Code session already imported** via
  `mimo session import-claude` (subcommand: `mimo session import-claude` — imports
  `~/.claude/projects` transcripts into mimocode's own store). `mimo session delete <id>` also
  exists.
- `mimo export [sessionID] [--sanitize]` / `mimo import <file>` — JSON session export/import
  (round-trip, `--sanitize` redacts transcript/file data).
- **Storage**: sessions live in a **SQLite database**, not per-session files:
  `mimo db path` → `/Users/rus/.local/share/mimocode/mimocode.db`. `mimo db` gives an interactive
  sqlite shell or runs a query (`--format json|tsv`); `mimo db migrate` migrates legacy JSON data
  into it.

## 4. Hooks / lifecycle events

Two independent, much stronger-than-screen-scraping mechanisms exist:

### 4a. ACP (Agent Client Protocol) server — `mimo acp`
`mimo acp` starts a JSON-RPC ACP server (Zed's Agent Client Protocol) over stdio/socket
(`--port`/`--hostname`/`--mdns`/`--cors`/`--no-auth`, same flags as `mimo serve`). Full Zod-typed
method surface was extracted from the binary, including:
- Client→agent: `initialize`, `authenticate`, `session/new`, `session/load`, `session/list`,
  `session/fork`, `session/resume`, `session/prompt`, `session/cancel`, `session/close`,
  `session/set_mode`, `session/set_model`, `session/set_config_option`.
- Agent→client (the interesting half for a host app): `session/update` (streamed content/diff/
  terminal chunks), **`session/request_permission`** (structured permission-ask RPC with
  `options: [{kind: allow_once|allow_always|reject_once|reject_always, name, optionId}]` —
  this is the real "waiting for approval" signal, not a UI string to grep for), plus
  `fs/read_text_file`, `fs/write_text_file`, `terminal/create|kill|output|release|wait_for_exit`.
- This is the same protocol IDEs (Zed) use to embed opencode-family agents — it is the highest-
  fidelity integration point for AGX if a pane can speak JSON-RPC instead of driving a TUI.

### 4b. HTTP+SSE server — `mimo serve` (headless server also implicitly started by the plain `mimo` TUI in-process)
Full REST route surface found in the binary (opencode-style):
`/session`, `/session/{id}`, `/session/{id}/abort`, `/session/{id}/children`,
`/session/{id}/command`, `/session/{id}/diff`, `/session/{id}/fork`, `/session/{id}/init`,
`/session/{id}/message`, `/session/{id}/message/{messageID}[/part/{partID}]`,
**`/session/{id}/permissions/{permissionID}`** (GET the pending permission / POST a reply),
`/session/{id}/prompt_async` (submit a prompt without blocking — the HTTP equivalent of seeding),
`/session/{id}/revert`, `/session/{id}/share`, `/session/{id}/shell`, `/session/{id}/summarize`,
`/session/{id}/todo`, `/session/{id}/unrevert`, `/session/status`, plus a global **`/event`** SSE
endpoint. Event-bus names recovered from the binary (published on `/event`): `session.idle`,
`session.updated`, `session.error`, `session.deleted`, `session.status`, `message.updated`,
`message.part.updated`, `installation.updated`, `file.edited`, and — the key one —
**`permission.asked`** / **`permission.replied`** (request/response pair on the bus). `mimo
attach <url>` lets a second CLI process attach its TUI to an already-running server started this
way, over `MIMOCODE_SERVER_PASSWORD`-protected Basic Auth if non-loopback.
- **Recommendation for AGX**: run each pane as `mimo serve --port <N>` (or let the default TUI
  bind its own local server) and integrate against `/event` (SSE) for `permission.asked` /
  `session.idle` instead of grepping the terminal screen. This is a structured, reliable
  "waiting-for-approval" signal.

### 4c. Plugin/hook API (in-process JS/TS plugins, `mimo plugin <npm-module>`)
The binary ships its own bundled documentation (`reference/hook-api.md`, `reference/plugin-api.md`,
`reference/tool-api.md` — read verbatim via `strings`, not from GitHub). Hook file shape:
```ts
import type { Hooks } from "@mimo-ai/plugin"
const hooks: Hooks = { "event.name": async (input, output) => { /* mutate output */ } }
export default hooks
```
Documented events: `tool.execute.before` (mutate `output.args`, or set `output.cancel`/
`cancelReason` to block a tool call), `tool.execute.after` (mutate result), `tool.definition`
(rewrite tool description/schema sent to the LLM), `chat.params`, `chat.headers`,
`experimental.chat.system.transform`, `experimental.chat.messages.transform`,
`experimental.session.compacting`, `chat.message`, `command.execute.before`, `shell.env`, and
**`permission.ask`** — but the doc explicitly says: *"Defined in the Hooks interface but not yet
wired in the permission system. Writing this hook is safe (no-op until upstream integrates it)."*
So the in-process hook for auto-allow/deny is a documented **no-op in v0.1.4** — use the ACP
`session/request_permission` RPC or the `/event` SSE `permission.asked`/`permission.replied` pair
instead (both are live, per §4a/4b). TUI plugins (separate `TuiPlugin` API: `api.command.register`,
`api.slots.register`, `api.event.on`, `api.kv`, `api.lifecycle`) exist for extending the terminal
UI itself, run in a separate thread, and need a restart to take effect — not relevant to AGX
embedding, but confirms plugin loading is real and documented.

### 4d. Fallback: on-screen text if AGX must screen-scrape
If none of the above are wired up, the permission dialog's English button labels are fixed
strings recoverable from the locale table: **"Allow once"**, **"Allow always"**, **"Deny"**
(keys `ui.permission.allowOnce/allowAlways/deny`). Seeing those three together on screen is the
TUI's "waiting for approval" signature. (Not tested live — TUI wasn't launched per instructions.)

## 5. Trust / first-run gates

- **Auth**: already logged in on this machine — `mimo providers whoami` → provider `MiMo`, user id
  `4234734566`; `mimo providers list` shows credentials at
  `~/.local/share/mimocode/auth.json` (Xiaomi `api` credential). First-run (per README) offers:
  MiMo Auto (anonymous, zero-config, "free for a limited time"), Xiaomi MiMo Platform (OAuth
  login), "Import from Claude Code" (migrates existing Claude Code auth), or a custom
  OpenAI-compatible provider — chosen interactively on first launch; not scriptable via a flag
  found in `--help` (no `--api-key`/`--login` flag on the default command).
- **Workspace trust gate** (confirmed in source, function `SY0`/`AF2`): on every launch of the
  default TUI command (unless `--trust` is passed), mimo resolves the target directory and
  classifies it as `trusted` / `untrusted` / `dangerous`:
  - `dangerous` = the directory **is the user's home directory or filesystem root** — always
    prompts (even if previously "trusted"), with an extra scary warning
    ("The model will have access to ALL your personal files...").
  - `untrusted` = any other directory not yet in the trusted list — prompts once, then persists.
  - `trusted` = previously approved — no prompt.
  - Trusted paths are persisted to **`~/.local/share/mimocode/trusted-workspaces.json`**
    (`{"version":1,"trustedPaths":[...]}`), guarded by a file lock.
  - **`--trust`** (boolean flag on the default command) **skips this entire check** — the
    condition in source is a plain `if (!A.trust) { ... }`, so passing `--trust` bypasses the
    prompt unconditionally, including for home/root. This is the flag AGX should pass when
    seeding a new pane non-interactively (project dirs are normally not home/root anyway).
- No separate "accept terms" gate was found blocking a seeded prompt beyond the trust dialog and
  (if never authenticated at all) the first-run provider-selection screen.

## 6. Config paths

From `mimo debug paths` (ground truth, run on this machine):
```
home    /Users/rus
data    /Users/rus/.local/share/mimocode
bin     /Users/rus/.cache/mimocode/bin
log     /Users/rus/.local/share/mimocode/log
cache   /Users/rus/.cache/mimocode
config  /Users/rus/.config/mimocode
state   /Users/rus/.local/state/mimocode
```
- Project config: `mimocode.json` / `mimocode.jsonc` in the project root, or `.mimocode/mimocode.json`
  (checked in that order); global config: `~/.config/mimocode/mimocode.json`. Schema:
  `https://mimo.xiaomi.com/mimocode/config.json`. `mimo debug config` prints the fully resolved
  config (merged project+global) — on this machine it includes `agent`, `mode`, `plugin`,
  `command`, and a live `mcp` block (this machine already has MCP servers configured, several
  with embedded API tokens — **not reproduced here**, see OPSEC note below).
- `mimo debug agent <name>` shows per-agent permission rules — shape is
  `{permission, action: allow|ask|deny, pattern}` (glob-matched), e.g. the default `build` agent
  allows `*` broadly but asks for `doom_loop` and `external_directory` outside a small allow-list
  of mimocode's own data dirs.
- Env vars seen: `MIMOCODE_BIN_PATH` (override resolved binary), `MIMOCODE_SERVER_PASSWORD` /
  `MIMOCODE_SERVER_USERNAME` (Basic Auth for `attach`/non-loopback `serve`),
  `MIMOCODE_EXPERIMENTAL_DISABLE_COPY_ON_SELECT`, `MIMOCODE_SHOW_TTFD` (both TUI feature flags),
  `XDG_DATA_HOME`/`XDG_CONFIG_HOME` respected for the (legacy-named) opencode-path auth helper.

**OPSEC note:** `mimo debug config` on this machine printed live MCP server definitions
containing bearer tokens/API keys for this user's own integrations (Mars MCP, Plane, etc.) —
intentionally excluded from this file; if AGX needs the config shape, regenerate `mimo debug
config` locally rather than copying secrets into docs.

## 7. Usage / limits

- `mimo stats` — token usage and cost statistics. Flags: `--days N` (default: all time), `--tools N`
  (top N tools, default all), `--models [N]` (show model breakdown, optionally top N),
  `--project <name>` (filter; empty string = current project, default = all projects).
- `mimo models [provider]` — lists available models. On this account:
  `mimo/mimo-auto`, `xiaomi/mimo-v2.5`, `xiaomi/mimo-v2.5-pro`, `xiaomi/mimo-v2.5-pro-ultraspeed`.
- No separate rate-limit/quota inspection command was found beyond `stats` (cost/tokens) and
  `providers whoami`.

## 8. Gaps

- **Did not verify whether `--prompt` on the interactive command auto-submits the turn** vs. just
  pre-filling the input box — inferred from source (`args.prompt` flows straight into the TUI
  bootstrap) but the task explicitly disallowed launching the TUI to confirm. Needs a live check
  (in a disposable dir, with `--trust`) before AGX relies on it as "fire and forget."
  - Update: since `mimo` already has `mimo run` for genuinely headless one-shot turns, if
    `--prompt` on the default command turns out to only pre-fill, AGX still has `mimo run` (real
    headless) or the ACP/`prompt_async` HTTP path (real programmatic seeding) as fallbacks.
- **`permission.ask` in-process hook is a documented no-op** in v0.1.4 — cannot auto-allow/deny
  from a plugin yet; must use ACP's `session/request_permission` or the HTTP `/event` SSE +
  `/session/{id}/permissions/{permissionID}` reply endpoint instead.
- The compiled binary is minified/bundled (Bun single-file executable) — no readable TypeScript
  source tree was available locally to double-check exact request/response JSON shapes beyond the
  Zod schemas recovered via `strings`; treat field names as high-confidence but verify against a
  live ACP/HTTP session before building a client.
- Did not test `mimo acp` or `mimo serve` live (would count as "launching" the agent runtime); the
  route/method inventory above is static analysis, not an observed wire capture.
- First-run provider selection (MiMo Auto vs OAuth vs "Import from Claude Code" vs custom
  provider) appears to be TUI-only with no CLI flag in `--help` — unclear if it can be
  pre-seeded/scripted for a fresh machine AGX might provision (this machine was already
  authenticated, so the flow itself wasn't observed).
