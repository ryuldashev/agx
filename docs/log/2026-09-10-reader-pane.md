# 2026-09-10 — markdown reader in the split pane (`session.reader.*`)

Branch `reader-pane-2026-09-10` off `origin/master` (ddda9df). Not deployed, not relaunched: the running
agx hosts live sessions. v1 (commit 39a9f64) floated the document in a HUD-style panel; Ruslan rejected
that look in the Debug demo ("into the right pane where the terminal runs, natively") — v2 below is
what landed. Rule text: `.claude/rules/control-api.md` → "Markdown reader".

## What
`agtermctl session reader open <path.md> --target <session>` shows a rendered markdown document in that
session's RIGHT split pane, live-reloading as the file changes on disk (scroll kept, idiomorph DOM patch);
`agtermctl session reader close --target <session>` gives the pane back. In-app twin of `~/mmee/reader`.

Product flow: an agent writes a `.md` (plan, report) and runs `agx reader plan.md`; the document shows
up beside the shell and follows every rewrite; the user reads without leaving the session. Exits: `agx
reader close` (or the agent when done) restores the split; ⌘D hides it the same way; the pane's
"Open in Reader" button moves the file into a standalone Reader window and frees the pane. One document
per session — a second open replaces the first.

## Built
- **agtermCore**: `Reader.swift` (`ReaderSpec` path + optional width, `ReaderLayout` 20…80 / default 45
  → `splitRatio`, `ControlReaderNode(path)`, `ReaderError`); `Session.readerSpec`,
  `readerSlotGeneration`, `readerShowedSplit`, `readerActive`; `AppStore.openReader` (shows a
  left-right split when there is none and records it; sets the ratio from `--size-percent` or the
  default only when it showed the split; shell keeps focus) / `closeReader` (closes the split it showed
  when no shell ever ran in it, hides it otherwise; a preexisting split stays); `setSplitVisibility(hide)`
  and `closeSplit` clear the reader. `Command.sessionReaderOpen/.sessionReaderClose`,
  `ControlActions.openReader/closeReader`, `ControlDispatcher+Reader.swift` (path text, absolute, control
  chars, percent 1…100), `ControlSessionNode.reader` read-back.
- **app**: `agterm/Reader/MarkdownReaderView.swift` (NSView over `ReaderWebView: WKWebView`; eval queue
  until `ready`; `setBase`; `render(text)`; navigation policy; missing-file banner; page tinted to the
  terminal background with appearance chosen by luminance; pane preset 14px + 28px margins injected as a
  `<style>`; `adjustFontSize`/`resetFontSize` 10…28; `static focused()`; "Open in Reader" button →
  MmeeReader `uz.marshub.mmee.reader` or the system `.md` handler, then `onPopOut`; `onFocusChange`
  from the web view's first-responder transitions), `ReaderFileWatcher.swift`, `ReaderView.swift`
  (`onPopOut` → `store.closeReader`, `onFocus` → `splitFocused = true`). `deckPane(.right)` swaps the
  terminal for `ReaderView` while `readerSpec` is set, with the same `paneDim` wash as an inactive shell;
  `AppActions.increase/decrease/resetFontSize` route to the focused reader first;
  `ControlServer+Reader.swift` refuses an unreadable file and posts `.agtermApplySplitRatio` so the live
  divider follows the ratio.
- **resources**: `agterm/Resources/reader/` = verbatim copy of `~/mmee/reader/web` (`SOURCE.md`,
  `make sync-reader`); folder resource in `project.yml`.
- **CLI**: `agtermctl session reader [open] <path> [--size-percent N]` (default subcommand; `~`/relative
  resolved against the caller's cwd), `session reader close`; `scripts/agx`: `agx reader <path>` /
  `agx reader close` (defaults to `$AGTERM_SESSION_ID`).
- **tests**: `ControlDispatcherReaderTests`, `AppStoreReaderTests` (tree read-back, split shown at the
  default ratio with the shell focused, width bounds, preexisting ratio kept, replace/generation, close
  restores or keeps the split, hide/close split drops the reader, overlay slot untouched, not
  persisted), `ControlProtocolTests` + `CommandsTests`, `agtermTests/ReaderPanelTests` (bundled page,
  build/teardown, pop-out button, zoom bounds, gates), `agtermUITests/ControlReaderUITests` (open shows
  the split at 0.55 and close takes it down, replace + width bound, missing file).
- **docs**: control-api rule, `site/commands.html`, `site/docs.html`, skill `reference.md` + `SKILL.md`,
  `README.md`, `site/llms.txt`.

## Gates (this branch, 2026-09-10, v2)
- `make build` — Debug build OK.
- `make lint` — zero findings (`AppActions.swift` sits at exactly 1000 lines, preexisting; the reader
  lookup went into `MarkdownReaderView.focused()` rather than growing it).
- `make test` — 2737 tests / 111 suites passed.
- `make test-app` — 265 tests passed (2 preexisting skips).
- `xcodebuild test … -only-testing:agtermUITests/ControlReaderUITests` — 3/3 passed.
- Manual, isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agx-rd`): split shows at 0.55, reload in
  place, dark tint, pop-out to MmeeReader, ⌘+/⌘− on the document, focus wash both ways.

## Try after relaunch
```
agtermctl session reader open ~/Downloads/coinshop-v2-vse.md --target active
agtermctl tree --json | python3 -c 'import json,sys; [print(s["name"], s.get("reader"), s.get("splitRatio")) for w in json.load(sys.stdin)["result"]["tree"]["workspaces"] for s in w["sessions"] if s.get("reader")]'
printf '\n## live\n- [x] reload works\n' >> ~/Downloads/coinshop-v2-vse.md     # re-renders in place
agtermctl session reader open ~/Downloads/coinshop-v2-vse.md --size-percent 60 --target active
agtermctl session reader close --target active
# from inside an agent pane:
agx reader docs/plan.md ; agx reader close
```
Eyeball: first paint ~1–2 s (WebKit cold start); click the document → left pane dims, ⌘+/⌘− zoom the
document; click the shell → reader dims; ⌘D hides split and reader; "Open in Reader" → MmeeReader window
opens, pane returns to the shell.

## Deviations from the brief
- **Split pane, not a floating panel** (Ruslan's call after seeing v1). The reader borrows the split's
  right pane instead of owning a slot with HUD chrome; ⌘D and `session split close` therefore close
  it, which v1 could not do.
- **Not the overlay slot**: sharing `overlayActive` would thread a third predicate through every
  `hudActive`/`programOverlayActive` site; the reader coexists with a HUD and a program overlay instead.
  ⌘W and `session overlay close` leave it alone.
- `--position` dropped (a pane has no anchor). Height is the pane's.
- Ratio is the split's persisted `splitRatio`; the reader itself is never persisted.
- agterm rule over brief: the new CLI verb lives in `SessionReaderCommands.swift` (extension) because
  `SessionCommands.swift` sat at the lint limits and a touched file is not split without asking.
- The "Open in Reader" button is visual-only chrome with a control twin (`open -a Reader <path>` +
  `session reader close`); no protocol command was added for it.

## Known gaps
- `session focus --pane right` / ⌘] target the split SURFACE; with a reader in the pane they are no-ops
  (the shell keeps focus). Clicking the document is the way in.
- No outline, find, PDF export (MmeeReader has them) — the button is the path to those.
- `.md` links inside a document open in the system's `.md` handler, not in the pane.
- Debug demo instance from this session: PID in the session notes; stop with SIGTERM when done.
