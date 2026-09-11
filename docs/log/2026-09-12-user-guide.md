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
