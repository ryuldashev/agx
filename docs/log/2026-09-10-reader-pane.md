# 2026-09-10 — markdown reader pane (`session.reader.*`)

Branch `reader-pane-2026-09-10` off `origin/master` (ddda9df). Not deployed, not relaunched: the running
agx hosts live sessions, so the manual check below is Ruslan's after a relaunch.

## What
`agtermctl session reader open <path.md> --target <session>` shows a rendered markdown panel over that
session's pane, live-reloading as the file changes on disk (scroll kept, idiomorph DOM patch);
`agtermctl session reader close --target <session>` takes it down. In-app twin of `~/mmee/reader`
(MmeeReader). Rule text: `.claude/rules/control-api.md` → "Markdown reader".

## Built
- **agtermCore**: `Reader.swift` (`ReaderSpec`, `ReaderLayout` 20…80 width / fixed 92 height /
  default `center-right` 45, `ControlReaderNode`, `ReaderError`); `Session.readerSpec` +
  `readerSlotGeneration` + `readerActive`; `AppStore.openReader/closeReader` (`AppStore+Panes`);
  `Command.sessionReaderOpen/.sessionReaderClose`; `ControlActions.openReader/closeReader`;
  `ControlDispatcher+Reader.swift` (path text, absolute, control chars, percent, `HudPosition.parse`);
  `ControlSessionNode.reader` read-back populated in `AppStore+ControlTree`.
- **app**: `agterm/Reader/MarkdownReaderView.swift` (NSView hosting WKWebView; eval queue until
  `ready`; `setBase` to the file's folder; `render(text)`; navigation policy: only the bundled page,
  http/mailto → browser, other files → NSWorkspace; missing-file banner), `ReaderFileWatcher.swift`
  (DispatchSource, survives atomic saves, 120 ms debounce, all state on its own queue),
  `ReaderView.swift` (NSViewRepresentable, frees the web view on dismantle);
  `WindowContentView+Detail.readerPanel` — its OWN always-present sibling at zIndex 2 (above scratch,
  below overlayPanel), hidden under a FULL overlay; `OverlayPanelStyle.reader` reuses HUD chrome and
  the nine-anchor offset math; `ControlServer+Reader.swift` (refuses an unreadable file).
- **resources**: `agterm/Resources/reader/` = copy of `~/mmee/reader/web` (index.html, app.js,
  reader.css, vendored markdown-it / footnote / highlight / idiomorph / DOMPurify / mermaid — 2.9 MB,
  mermaid lazy-loaded only for docs that use it), `SOURCE.md`, `make sync-reader`; folder resource in
  `project.yml`, excluded from sources.
- **CLI**: `agtermctl session reader [open] <path> [--position P] [--size-percent N]` (default
  subcommand `open`; `~` and relative paths resolved against the caller's cwd → socket carries an
  absolute path), `session reader close`. `scripts/agx`: `agx reader <path> [--target ID]` /
  `agx reader close` (defaults to `$AGTERM_SESSION_ID`).
- **tests**: `ControlDispatcherReaderTests`, `AppStoreReaderTests` (tree read-back, nil omission,
  bounds, replace/generation, overlay-slot independence, not persisted), `ControlProtocolTests` +
  `CommandsTests` additions, `MockControlActions`; app-hosted `agtermTests/ReaderPanelTests`
  (style geometry, bundled page present, view build/teardown, gates untouched); e2e
  `agtermUITests/ControlReaderUITests` (open/read-back/close, replace + alias + bound, missing file).
- **docs**: control-api rule (catalog + section), `site/commands.html` (`session reader` nav +
  section), `site/docs.html` ("Markdown reader" under surfaces), skill `reference.md` + `SKILL.md`.

## Gates (all run on this branch, 2026-09-10)
- `make build` — Debug build OK (first attempt failed on Swift 6 strict concurrency in the watcher; fixed
  by keeping its state on its own queue and hopping callbacks to the main actor).
- `make lint` — zero findings (the new CLI command lives in `SessionReaderCommands.swift` as an
  extension, because `SessionCommands.swift` sat at the 800-line type / 1000-line file limits; per the
  rule the touched file itself was NOT split).
- `make test` — 2733 tests / 111 suites passed.
- `make test-app` — 265 tests passed (2 pre-existing skips).
- `xcodebuild test … -only-testing:agtermUITests/ControlReaderUITests` — 3/3 passed in an isolated
  instance (open/read-back/close, replace + alias + width bound, missing file refused).

## Try after relaunch
```
agtermctl session reader open ~/Downloads/coinshop-v2-vse.md --target active
agtermctl tree --json | python3 -c 'import json,sys; [print(s["name"], s.get("reader")) for w in json.load(sys.stdin)["result"]["tree"]["workspaces"] for s in w["sessions"] if s.get("reader")]'
printf '\n## live\n- [x] reload works\n' >> ~/Downloads/coinshop-v2-vse.md     # panel re-renders in place
agtermctl session reader open ~/Downloads/coinshop-v2-vse.md --position center-left --size-percent 60 --target active
agtermctl session reader close --target active
# from inside an agent pane:
agx reader docs/plan.md ; agx reader close
```
Things to eyeball: first paint ~1–2 s after open (WebKit process cold start — not a render bug, same as
MmeeReader); dark/light follows the system; clicking the document focuses the web view, clicking the
terminal returns focus; `session hud` over the reader; `session overlay open` (full) hides it and close
shows it again; ⌘W does NOT close the reader (own slot — see gaps).

## Deviations from the brief
- **Own slot, not a third occupant of the overlay slot.** Sharing `overlaySurface`/`overlayActive` would
  have required threading a third predicate through every `hudActive`/`programOverlayActive` site
  (focus routing, zoom arms, `overlay.text/copy/result/resize` refusals, ⌘W ladder) — the rule says
  never to spell that predicate inline, and each site would need its own reader refusal + test. A
  sibling slot (`Session.readerSpec`) touches none of it, and a document legitimately coexists with a
  HUD (progress) or a program overlay. Cost: ⌘W and `session overlay close` do not take the reader
  down; only `session reader close` and closing the session do.
- No `TerminalSurface` conformance: the web view is owned by the representable and freed on dismantle;
  nothing else needs to address it (no zoom, no `surface:<id>` node). `promoteToPrimaryPane` etc. would
  have been dead no-ops.
- `--position`/`--size-percent` accepted (cheap, reused `HudPosition` + HUD offsets); height is fixed
  (`ReaderLayout.heightPercent` 92), no caller override.

## Known gaps
- No manual check in the running app (relaunch forbidden in this session) — e2e UI test covers the
  socket/tree contract, not pixels. First relaunch is the visual check.
- Reader is not persisted (by design, like the HUD): gone after relaunch.
- No outline sidebar, find, font toggles, PDF export (MmeeReader has them) — v1 is render + live reload.
- `.md` links inside a document open in the system's `.md` handler (MmeeReader on this Mac), not in
  the panel.
- `session overlay close` / ⌘W leave the reader alone (see deviations).
- The web view takes first responder on click; the deck's focus routing does not know about it, so a
  session switch and back lands focus on the terminal, which is the intended default.
