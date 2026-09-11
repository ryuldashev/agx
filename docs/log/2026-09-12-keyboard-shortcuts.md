# 2026-09-12 — Keyboard Shortcuts sheet

## What shipped

A generated "Keyboard Shortcuts" reference, rendered live from the current keymap in the markdown
reader pane. Help ▸ Keyboard Shortcuts… (⌘/) and a command-palette row open it.

- `agtermCore/Sources/agtermCore/ShortcutsSheet.swift` — host-free generator. Takes a `Keymap`,
  returns the sheet as markdown: grouped tables (Sessions / Move between sessions / Workspaces /
  Panes & splits / Windows / View / Palettes / Quick terminal / Font size), one action per row, keys
  as `<kbd>` capsules resolved from `Keymap.equivalent` + `sequences` (so a rebind moves the sheet).
  Keyless actions read *palette only*. Renders the `global-hotkey` as a row under Quick terminal and a
  "Your custom commands" section from `keymap.commands`. `coveredActions` lists every built-in it
  places; a test pins it equal to `BuiltinAction.allCases`, so a new action can't silently drop off.
- `BuiltinAction.keyboardShortcuts` (`keyboard_shortcuts`, default ⌘/ — verified free in the shipped
  keymap). Rebindable and control-listable like any other built-in.
- `PaletteCommand.keyboardShortcuts` — title "Keyboard Shortcuts…", gated on an active session (the
  reader hosts in the session's split pane), dispatches to `AppActions.showKeyboardShortcuts()`.
- `AppActions+Shortcuts.swift` — `showKeyboardShortcuts()`: regenerates the sheet to
  `<stateDir>/keyboard-shortcuts.md` on each invocation and opens it via `store.openReader(...)`.
  (Split out of `AppActions.swift` to keep that file under the 1000-line lint limit.)
- Help menu item + the palette row.
- `Chord.kbdGlyphs` (in `Keybind.swift`) — the ordered per-glyph list behind `<kbd>` capsules;
  `glyphString` now joins it, no behavior change.
- `MarkdownReaderView.embeddedCSS` — added the `<kbd>` capsule styling and the right-aligned/nowrap
  Keys column (`td:has(> kbd:first-child)`). Put HERE, not in `Resources/reader/reader.css`, because
  that dir is a verbatim `make sync-reader` copy of `~/mmee/reader/web`; the reader already injects
  this `<style>` on top of the synced page for pane-specific rules.

## Where it lives / how the pieces connect

Menu/palette → `showKeyboardShortcuts()` → `ShortcutsSheet.markdown(keymap:)` → write to state dir →
`AppStore.openReader` → `ReaderView`/`MarkdownReaderView` (the existing reader pane) → bundled
`Resources/reader` page renders it, `embeddedCSS` styles the capsules.

## Base branch note

Branched from **`reader-pane-2026-09-10`**, not `origin/master`: the reader pane (`agx reader`,
`MarkdownReaderView`) this feature renders through is on that local branch (5 commits off master,
master is its ancestor) and is not yet pushed to origin. `origin/master` lacks the reader entirely, so
it could not host this work. `reader-pane-2026-09-10` is the true dependency base.

## Gates

- `swift test` (agtermCore): green for the changed areas. Updated `BuiltinActionTests` (46→47 + the
  shipped-chord table), `PaletteCatalogTests` (title order, count 50→51, builtinAction, needSession
  set), `SocketClientTests` (the byte-identical `keymap list` fixture gains a `keyboard_shortcuts`
  row), plus new `ShortcutsSheetTests`. NB: `OpenCodeStatusHookTests` flake under full-suite
  parallelism (pass in isolation) — pre-existing, unrelated.
- Debug build: **succeeds**.
- `make lint`: **clean**.
- Hosted (`agtermTests`): `AppActionsPaletteTests`, `ReaderPanelTests` pass.

## Not verified / follow-ups

- **Live menu click not run end-to-end.** The targeted Help-menu XCUITest could not start its
  automation runner in this environment ("Timed out while enabling automation mode" — a known
  launch-init flake, likely contending with two other sessions building concurrently), not a logic
  failure. The menu wiring is one Button matched by title (build-verified); the generate→reflect logic
  is unit-tested including `aRebindMovesTheSheet`.
- **Screenshot** `docs/screenshots/keyboard-shortcuts.png` was produced by rendering the *real*
  generator output through the *actual* bundled reader assets (`Resources/reader` + the injected
  `embeddedCSS`) in headless Chrome — a faithful, deterministic capture — rather than a live-window
  grab (no safe automated way to screencapture the dev window without risking the live app, which
  shares the process name "agx").
- **Rebind reflection** shown via unit test rather than by editing the user's real
  `~/.config/agterm/keymap.conf` (safer — no live-config mutation). At runtime the sheet regenerates
  on each ⌘/, so a reload + reopen reflects a rebind.
- **Considered but not added:** a dedicated `keyboard.shortcuts` control command. The reader already
  has full control coverage (`session.reader.open`), and the sheet is reachable by a human via ⌘/ /
  menu / palette (the task's ask). A control twin could regenerate + open the file for in-pane agents.

## Parallel-work caution

Two other sessions (`guide-2026-09-12`, `onboarding-2026-09-12`) are editing the SAME Help menu block
and their own generated pages. My menu diff is a single Button + Divider for a trivial merge. Deploy
was HELD (see report) — three branches touch the same menu and none is merged to master; a lone deploy
would ship an app missing the other two features and be overwritten minutes later. Merge first, deploy
once.
