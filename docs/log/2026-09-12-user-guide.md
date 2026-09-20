# 2026-09-12 — AGX user guide (`docs/guide/`, Help ▸ agx Guide…)

Branch `guide-2026-09-12` off `26c9fd4` (`agent-profiles-2026-09-11`, the deployed commit — NOT
`origin/master`, which lacks the reader pane, failover, and agent profiles the guide describes and the
Help item depends on). Merges into master together with those branches.

## What
The fork's own user documentation, one level above agterm's: how a day with several agents works in
AGX and what exists for it. `docs/guide/` — `README.md` (why + "AGX in 5 minutes" + chapters),
`model.md`, `agents.md`, `driving.md`, `reader.md`, `keyboard.md`, `settings.md`; troubleshooting
links to the existing `docs/troubleshooting.md`. ~620 lines total, English, relative links, three
existing screenshots. Upstream's docs are named once (README) as the low-level control API reference.

Sources: README, FORK.md, ui-lexicon (tokens used verbatim), troubleshooting, ADR 0001–0003, logs
2026-09-02…09-11, `scripts/agx`, the agent manifests, `agtermctl keymap list`, SettingsView.

## Built
- **Help ▸ agx Guide…** (first item) and palette `agx Guide` (`PaletteCommand.openGuide`, no keymap
  action). `AppActions+Guide.swift`: opens `Contents/Resources/docs/guide/README.md` in the active
  session's reader (same path as `agx reader`, split ratio posted); no session → system `.md` handler.
  `AppActions.swift` sits at 1000 lines, hence the extension file.
- Help ▸ "Developer Documentation (agterm)…" renamed **"agterm Control API Reference…"**.
- **Bundling**: `project.yml` post-build phase "Bundle user guide" copies `docs/guide`,
  `docs/troubleshooting.md`, `docs/ui-lexicon.md` and only the screenshots the guide references into
  `Contents/Resources/docs/`, keeping the repo layout so relative links resolve. Runs before the CLI
  phase, so the re-seal covers it.
- **Reader follows `.md` links in place**: `MarkdownReaderView.onOpenMarkdown` → `ReaderView` →
  `store.openReader(session, spec:)`; a relative `.md` link now replaces the document in the pane
  (`tree.reader.path` follows) instead of popping out to the system handler. Non-`.md` files and web
  links unchanged.
- README: guide linked in the header line and under Documentation.

## Gates
- `make build` (Debug) — BUILD SUCCEEDED; `Contents/Resources/docs/{guide,screenshots,troubleshooting.md,ui-lexicon.md}` present.
- `swift test` — 2785 tests / 116 suites passed.
- `make lint` — zero findings.
- `make deploy` — see the commit after this one.

## Not done / open
- `keyboard.md` carries a TODO: link the generated **Help ▸ Keyboard Shortcuts** sheet once
  `shortcuts-sheet-2026-09-12` lands (that branch also edits the Help block, `PaletteCatalog`,
  `PaletteCatalogTests` and `MarkdownReaderView.embeddedCSS` — trivial merge, both sides add lines).
- The guide is a first draft for Ruslan's read (`agx reader docs/guide/README.md`); nothing went
  outside.
- No new screenshots; the three used are upstream's (`main`, `dashboard`, `floating-overlay`,
  `agent-prompt`, `action-palette`).
- Not verified by hand: the Help item in a Debug instance (a fresh instance opens the guide in whatever
  session is selected; the deployed app needs a relaunch to carry the new menu).
- `make test-app` not run (hosted suite); `swift test` + `make lint` + Debug build + Release build are the
  gates below.

## x5 pass (same branch, review → rewrite)

Rewrote the guide from a feature reference into a day-with-agents narrative. Same branch/worktree,
still off the deployed `26c9fd4` base (not `origin/master`, which lacks reader/failover/profiles —
"от origin/main" in the brief is impossible without reverting the app; kept the v1 base. **Decided
myself.**)

### What changed
- **Two new opening chapters.** `why.md` (three problems with N agents in tabs → what AGX does →
  what AGX is *not*: not an orchestrator/chat-client/sandbox) and `a-day.md` (one working day,
  08:50→next-morning, every step naming what is on screen in ui-lexicon tokens + the one command).
  `a-day.md` is chapter 2, right after Why.
- **`first-run.md`** — new: TCC (why "agx would like to access…", the What's-running-now list, stable
  Developer ID vs ad-hoc), the three installers file-by-file with a "what happens to your existing
  hooks/skills" column and an **Undo** line each, Settings ▸ Agents, first spawn, a reversibility
  table. Sourced from `PermissionPrimer.swift`, `AgentHooksInstaller.swift`, the onboarding
  worktree's `installers-audit.md`, and the live `~/.claude/settings.json` / `~/.config/agx/agent-status`.
- **`driving.md`** — added a "first five commands" quickstart with **real captured output** (`agx
  context`, `agx run`, `agx spawn --json`) and a dedicated **`active` is almost never your own
  session** section (the most common agent mistake — was absent in v1).
- **`model.md`, `agents.md`, `reader.md`, `keyboard.md`, `settings.md`** — recut into tables
  (what/where/key), shorter paragraphs, `Try it:` blocks, one-sentence takeaways.
- **`README.md`** — new chapter order Why → A day → First run → Model → Agents → Driving → Reader →
  Keyboard → Settings → Troubleshooting; "AGX in 5 minutes" kept.
- **keyboard.md TODO resolved.** `shortcuts-sheet-2026-09-12` has landed **Help ▸ Keyboard
  Shortcuts…** at chord **⌘/** (`BuiltinAction.keyboardShortcuts`, menu `agtermApp+Menus.swift:400`).
  Referenced the real menu item + chord; dropped the HTML TODO comment. That branch merges alongside
  this one.

### Command verification (every snippet run against the live `agtermctl` / Debug instance)
Confirmed real, kept: `agx context/run/spawn/reader/schedule/usage`; `workspace defaults`
(`--dir/--agent/--background/--background-opacity/--background-fit`); `session reader open
--size-percent` (20–80, "45 for a split the reader has to show" — matches); `session hud open`
(`--detail/--spinner/--position/--size-percent`); `session failure <error> --handoff/--message`;
`session overlay open "<cmd>" --pane/--size-percent`; `session scratch on --command`; `restore
list|open|last`; `session status/text/type/notify/pick`; default ladder `["opus[1m]","sonnet[1m]"]`
(`AgentFailover.swift:131`); undo grace = **3 s** (`pendingCloseGraceInterval`); journal at
`~/Library/Application Support/agx/journal.jsonl`; abduco detach key **`^\`** (ADR 0001);
attention order **blocked→active→completed** (`attentionRank`); collapsed rollup
**blocked>completed>active** (`rollupRank`).

**Fixed from v1:**
- v1 said `agx run … [--keep]` — **the `--keep` flag does not exist** in `scripts/agx cmd_run`
  (only `--pane`). Removed everywhere.
- v1's model.md gave the collapsed-rollup order as "`⛔` beats `✓` beats `●`" in prose but the a-day
  narrative and attention nav conflated the two orders; separated them (rollup vs attention are
  different ranks) and corrected the wording.
- v1's failover/attention text implied the `bell` and the nav walk the same set; they don't — `bell`
  counts blocked+completed, the nav/list walks every non-idle session. Made explicit.
- No outright fabricated commands beyond `--keep`; v1's command surface was otherwise accurate.

### Screenshots
New, captured from a real isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agxg`, populated tree,
`screencapture -l <windowid>`, ≤1600px):
- `guide-option-hints.png` — the ⌥ hint panel (`AGX_HINTS_ALWAYS=1`), title-bar + sidebar tokens.
- `guide-reader-pane.png` — this guide open in the split pane beside the shell.
- `guide-sidebar-glyphs.png` — sidebar with per-session glyphs and a **collapsed `mars` row showing
  its count `4` + the orange blocked rollup**.

**Not captured (Accessibility denies `osascript` keystrokes in this session, so ⌘, / menu-driven
GUI is unreachable) — wanted frames, left without an image rather than a broken link:**
- **Settings ▸ Agents** with "Found on This Mac" and Connect buttons.
- **Install Agent Status Hooks result window** (`AgentHooksResultView`) — one row per agent with
  tiles + ✓/⚠/– marks.
- **A failover session** `"<name> → Codex"` beside the pane that ran dry, plus the failover
  notification.
Prose in `settings.md` / `first-run.md` / `agents.md` covers these; add the images when a session
with Accessibility (or hands-on capture) is available.

### Size
855 lines across 10 chapters (budget ≤1100). Debug instance stopped; `/tmp/agxg` left for reuse.
