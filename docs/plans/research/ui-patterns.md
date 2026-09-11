# UI Patterns Research — Welcome/Getting-started panel + capability tracker

Status: DONE. All refs verified against this worktree's checkout.

## 1. First-run pieces: FirstRunWelcome, TCC Permissions, About

**FirstRunWelcome** — host-free due-decision + copy, `agtermCore/Sources/agtermCore/FirstRunWelcome.swift:5-40`.
- `priorStateNames = ["settings.json", "workspaces.json", "windows"]` (:8) — control socket excluded on purpose
  (bound before scene `.task`, so its presence proves nothing about earlier launches).
- `hasPriorState(in:)` (:29-31): file-existence check, MUST run before the app writes anything (window
  bootstrap saves within a second of scene appearing).
- `isDue(welcomeShown:hasPriorState:)` (:37-39): `welcomeShown != true && !hasPriorState` — two different
  questions (never-shown-flag vs. genuinely-fresh-install) so an upgrading user isn't treated as first-run.
- Trigger: `agtermApp.swift` computes `hadPriorState`/`welcomeDue` in `init()` (:54, :65-66), BEFORE
  `restoredLibrary()` runs. Presented from the `WindowGroup`'s `.task` at `agtermApp.swift:211-218`:
  `if welcomeDue { WelcomeAlert.presentOnce(settingsModel:) { if permissionsPrimerDue { ... } } } else if
  permissionsPrimerDue { ... }` — permission wall chained off welcome's completion so two modals never stack.
- `WelcomeAlert` (`agterm/WelcomeAlert.swift`) is a plain `NSAlert` (not a SwiftUI Window/Panel):
  `presentOnce(settingsModel:then:)` (:20-30) marks `settingsModel.setWelcomeShown(true)` BEFORE running the
  modal (so a cancelled install can't re-arm it), hops via `DispatchQueue.main.async` out of the caller's
  `.task` (`runModal()` inside a Task returns `.abort` immediately — real trap, note it), then `present()`
  builds the alert via `makeAlert()` (:42-65, split out so a hosted test can inspect layout without a modal
  loop) — two `NSButton` checkboxes in an `NSStackView`, `AlertAccessoryLayout.indent(...)` aligns them under
  the message text. `isSuppressedForUITest` (:12-14) gates every XCUITest launch.

**TCC Permissions wall** — `docs/log/2026-09-03-tcc-permissions.md` explains WHY (child processes in a pane
attribute their TCC prompts to agx, not to the command that actually asked).
- `PermissionPrimer` (agtermCore, host-free) — `agtermCore/Sources/agtermCore/PermissionPrimer.swift`.
  `Area` struct (:28-54, id/title/reason/grant), `Grant` enum (:17-25: `.probe(path:)` for the 5 file-system
  areas that raise a real dialog on read, `.settings(anchor:)` for the 3 that have NO probe API at all —
  Full Disk Access / Accessibility / Screen Recording, opened via `x-apple.systempreferences:` anchor,
  `:76-105`). `Status` enum (:57-68: granted/denied/absent/unknown). **This is the closest reusable
  "PermissionsStatus-like model" — but it is a static catalog + due-decision, not a live status query: macOS
  has no query API for these areas, only a probe-by-reading side effect** (comment at :14-16). `isDue(primerShown:)`
  (:143-152) is intentionally NOT gated on `hasPriorState` like welcome (upgrade users need it too).
- App-side raiser: `agterm/Permissions/PermissionProbe.swift` — reads a real file off-main to trip the actual
  macOS dialog (no API exists for a programmatic request on file-shaped services).
- `PermissionsAlert` (`agterm/Permissions/PermissionsAlert.swift`) — same NSAlert shape as Welcome:
  `presentOnce(settingsModel:library:)` (:24-31) marks shown before modal, hops main.async; `present(library:)`
  (:35-57) **loops** (not recurses) so "What's running now…" (`presentRunning`) can return to the wall any
  number of times without stacking `runModal()` sessions — reusable idiom if a Welcome panel needs a
  "show me details" sub-dialog. Checkboxes built from `PermissionPrimer.probeableAreas` (:44).

**About panel** — `agterm/agtermApp+Menus.swift:419-443`, `showAboutPanel()`: **not a custom window at all**,
it's `NSApplication.shared.orderFrontStandardAboutPanel(options:)` with `.credits` set to an
`NSMutableAttributedString` (clickable homepage link + "A fork of X by Y, MIT" in secondary color) and
`.version` overridden to the short git commit on release builds.

**Conclusion for a new Welcome/Getting-started panel**: there is NO precedent in this codebase for an
auxiliary SwiftUI `Window`/`WindowGroup` scene or `openWindow(id:)` beyond the single terminal
`WindowGroup` (`agtermApp.swift:99`, claimed via `openWindow(id: Self.windowGroupID)` at :139/:255) and the
`Settings {}` scene (:229-231, opens `SettingsView`). Every Help-menu extra (Welcome, Permissions, About) is
an `NSAlert` or the stock About panel. A **checklist with per-row action buttons** (which the ask wants) has
no NSAlert precedent — the closest layout analog is SwiftUI (`AgentsSettingsView`, section 3 below). Two
honest options, worth flagging to the user before building:
(a) NSAlert like Welcome/Permissions — consistent with "Help ▸ X…" opening a modal, but NSAlert accessory
views make a scrollable checklist with buttons awkward (manual NSStackView layout, as Welcome/Permissions
already do for two checkboxes — a longer list gets ugly fast);
(b) a new tab in `SettingsView` (`agterm/Views/SettingsView.swift:22-45`) — reuses the existing `Form`/
`TabView` chrome, `SettingHint`, and the exact "Connected list + Found-on-this-Mac + action button" shape
from `AgentsSettingsView`, but a Getting-started panel is conceptually not a *setting*.
No existing pattern rules either out; this is a real judgment call, not something to infer silently.

## 2. Help menu block (verbatim order)

`agterm/agtermApp+Menus.swift:399-417`, `CommandGroup(replacing: .help)`:
```
1. Button("\(Brand.productName) on GitHub…")                    → NSWorkspace.shared.open(Brand.homepage)
2. Button("Developer Documentation (\(Brand.upstreamName))…")    → opens Brand.upstreamDocs + "#agtermctl"
   Divider()
3. Button("Install Command Line Tool…")     → CLIInstaller.run()
4. Button("Install Agent Status Hooks…")    → AgentHooksInstaller.run()
5. Button("Install Agent Skill…")           → SkillInstaller.run()
   Divider()
6. Button("Permissions…")                   → PermissionsAlert.present(library: library)
```
A new "Getting Started…" / "Welcome…" item is a one-line addition inside this same `CommandGroup`, most
naturally its own line or grouped with the top pair (GitHub/Docs are "learn more", Permissions is "revisit
a wall") — e.g. `Button("Getting Started…") { WelcomeAlert.present(...) }` right after the Divider before
`Permissions…`, or as its own trailing item. Note: `About Agterm` (`showAboutPanel()`) lives in a SEPARATE
`CommandGroup(replacing: .appInfo)` at :50-51, not in this Help block — don't confuse the two when wiring.

## 3. Views/ shared components, Agents-settings analog, status glyphs

No `.agxPanel` modifier or generic "SectionHeader"/"capsule button" component exists — that guess in the ask
was wrong; searched `agterm/Views/*.swift` for `agxPanel`/`SectionHeader`/`StatusGlyph`/`SessionStatus` and
only `StatusGlyph.swift` matched literally.

**AgentsSettingsView** (`agterm/Views/AgentsSettingsView.swift`) is the closest analog to a checklist with
per-row action buttons, and it's the right template to copy the shape of:
- `Section("Connected")` (:21-32): list of already-added rows (`AgentRow`, :130-...) + an "Add…" button.
- `Section("Found on This Mac")` (:34-60): `available` (computed :120-123, detected-minus-already-connected)
  rendered as `HStack { VStack(name + monospaced binary path) ; Spacer() ; Button("Connect") { ... } }`
  (:42-53) — exactly the "capability discovered, one-tap to adopt" shape a Getting-started checklist wants.
  `detected` is `@State`, populated `.onAppear` and by an explicit "Rescan" button (:57, :87) — NOT live/
  reactive, deliberately (comment :15-16: probing PATH on every keystroke would stat disk while typing).
- `SettingHint` (`agterm/Views/SettingsView.swift:70-78`) — the one reusable micro-component: small
  secondary-color caption text under a control. Not private, explicitly exported for cross-file reuse.
- Empty-state text pattern: plain `Text(...).font(.caption).foregroundStyle(.secondary)` (:22-26, :36-40),
  no dedicated "empty state" view type.

**Status glyph vocabulary**: `StatusGlyph` (`agterm/Views/StatusGlyph.swift:8-20`) is a SwiftUI `View`
wrapping `Image(systemName:)` (SF Symbols, not literal glyph characters like ✳/●/◐) tinted via
`GhosttyApp.shared.statusColor(for:override:)`. Symbol name resolved by `GhosttyApp.statusSymbolName(for:
override:)` — search `agtermCore`/`agterm` for `AgentStatus`/`statusSymbolName` if a Getting-started
checklist wants a "done/pending" glyph; it mirrors the sidebar's AppKit `StatusIconView` so both draw from
the same resolver (comment :6-7) — don't invent a third glyph source.

## 4. Persistence pattern (state-dir JSON stores)

Three near-identical implementations, all in `agtermCore` (host-free), all following: struct wrapping a
`directory: URL`, `fileURL` computed property, `load()` that NEVER throws (missing/corrupt/wrong-version →
safe default), `save(_:)` that creates the directory then writes via `Data.write(options: .atomic)`
(temp-file-then-rename, crash-safe).

- **`PersistenceStore`** (`agtermCore/Sources/agtermCore/PersistenceStore.swift:8-40`) — the original/
  canonical shape. `defaultDirectory` (:21-24) = `~/Library/Application Support/<Brand.stateDirectoryName>`
  (via `FileManager.default.urls(for: .applicationSupportDirectory, ...)`). `fileName` is an init param
  (defaults `"workspaces.json"`).
- **`SettingsStore`** (`agtermCore/Sources/agtermCore/SettingsStore.swift:6-38`) — `settings.json`, same
  directory root as the workspace snapshot so `AGTERM_STATE_DIR` overrides both. `load()` (:22-26) falls back
  to `Self.seededDefault` (`AppSettings(theme: AppSettings.defaultTheme)`, :29) on any failure. `save(_:)`
  (:32-38) uses `JSONEncoder` with `[.prettyPrinted, .sortedKeys]`.
- **`ScheduleStore`** (`agtermCore/Sources/agtermCore/ScheduledSession.swift:62-91`) — `scheduled.json` +
  a version-gated wrapper file (`ScheduledSessionsFile`, :48-57, `currentVersion = 1`, checked on load
  :78-80: wrong version → treated as absent, returns `[]`) PLUS a sibling directory
  (`scheduled/`, `briefDirectoryName`) for large per-item text blobs the JSON file doesn't carry
  (`writeBrief`/`briefFile(for:)`, :89-...). `encoder.dateEncodingStrategy = .iso8601` (:85) — needed because
  `ScheduledSession` carries `Date` fields; skip this if a new store has none.

**For `<stateDir>/onboarding.json`**: copy `SettingsStore`'s shape almost verbatim (simplest of the three —
no version-file wrapper needed unless the schema will evolve; if it might, copy `ScheduleStore`'s
`...File { version; items }` wrapper instead, since a onboarding.json is unlikely to need a sibling
directory for blobs). Root it via the same `directory: URL` the app already threads through — `agtermApp.init`
resolves `stateDirectory` once at `agtermApp.swift:52-53` and passes it to `SettingsStore`, `ScheduleStore`
(via `SessionScheduler`), and `ActionJournal.shared.configure(directory:)` — a new onboarding store should be
constructed alongside them in `init()`, not re-derive the directory itself.

## 5. Control API pattern (tree field + dispatcher + CLI + tests + docs) + ActionJournal

Full round-trip for one command family, using `schedule.*` as the worked example (smallest complete one):

1. **Protocol enum case** — `agtermCore/Sources/agtermCore/ControlProtocol.swift:90-93`:
   `case scheduleAdd = "schedule.add"`, `scheduleList = "schedule.list"`, etc. (dot-namespaced raw string).
2. **`ControlActions` protocol method** — declared in `agtermCore/Sources/agtermCore/ControlDispatcherOptions.swift:139-142`
   (`func scheduleList() -> ControlResponse`, host-free signature).
3. **Dispatcher switch wiring** — `ControlDispatcher.swift:203-204`: `case .scheduleAdd, .scheduleList, ...:
   return dispatchScheduleCommand(request)`, which lives in its own extension file
   `agtermCore/Sources/agtermCore/ControlDispatcher+Schedule.swift:6-25` (host-free validation: time
   grammar, brief non-empty, mutually-exclusive args — pure logic, no store access) and forwards to
   `actions.scheduleList()` etc.
4. **App-side implementation** — `agterm/Control/ControlServer+Schedule.swift:49-52`:
   `func scheduleList() -> ControlResponse { ...; ControlResponse(ok: true, result: ControlResult(scheduled:
   scheduler.nodes())) }` — this is where store/live-state access happens (needs `SessionScheduler`).
5. **Tree/result payload field** — `ControlResult.scheduled: [ControlScheduledNode]?`
   (`ControlTreeNodes.swift:382`, initializer param :390, assignment :404) is how a NEW read-only field on
   the response/tree gets added: an optional array on the `ControlResult`/tree-node struct, defaulted nil so
   old clients aren't affected. Top-level tree wiring: `AppStore+ControlTree.swift:26` (closure param
   `scheduled: () -> [ControlScheduledNode]? = { nil }`) called at :102 (`scheduled: scheduled())`) —
   and the REAL closure supplying live data is injected app-side at `agterm/Control/ControlServer.swift:661`:
   `scheduled: { [weak self] in self?.scheduledNodes() }`.
6. **CLI (`agtermctl`)** — `agtermCore/Sources/agtermctlKit/ScheduleCommands.swift:6-10`: a `Schedule:
   ParsableCommand` (ArgumentParser) with `subcommands: [Add.self, List.self, Cancel.self, Run.self]`, each
   conforming to `RequestCommand` (protocol requiring `makeRequest() -> ControlRequest`). Registered as a
   top-level subcommand at `agtermCore/Sources/agtermctlKit/Commands.swift:91-98`
   (`Agtermctl.configuration.subcommands` array — appending `OnboardingCLI.self` or similar here is the only
   registration point).
7. **Tests / command-count**: **no hard-coded command-count assertion exists** anywhere (checked
   `agtermCore/Tests/agtermctlKitTests/CommandsTests.swift` and grepped `agtermUITests`/`site` for
   "command count" — none found), so adding a command costs no test-count bookkeeping. What DOES need
   updating per `CLAUDE.md`'s cross-surface-contracts rule: `site/commands.html` (canonical command
   reference — schedule's block starts at `site/commands.html:1908`, one `<section id="...">` per command
   family, one sub-block per verb e.g. `:1930-1937` for `schedule.add`) and the bundled
   `plugins/agterm/skills/agterm/` skill docs (per `CLAUDE.md`'s cross-surface-contracts section).
8. **ActionJournal hook for "capability discovered"**: `agtermCore/Sources/agtermCore/ActionJournal.swift`
   (host-free, `@unchecked Sendable`, one JSON line per event, rotates at 8MB). `log(_ kind: String, _
   fields: [String: String])` (:44-55) — flat string-pair fields only ("this is a grep target, not a data
   model", :43). Existing call sites and their `kind`:
   - `"control"` — **every mutating control request**, logged once at the single choke point
     `agterm/Control/ControlServer.swift:407-419` (`private func journal(_ request:)`), which is called from
     `dispatch(_:)` and explicitly SKIPS read-only commands (`tree`, `eventsRead`, `windowList`,
     `sessionText`, :409). Fields: `cmd` (raw command string), `target`, `mode`, `name` if present.
     **This is the single best hook for "capability discovered" for anything that is already a control
     command** — spawn (routes through `session.*`/`schedule.add` etc.), reader (`session.reader`),
     schedule, dashboard, failover config changes: all already produce a `"control"` journal line with
     `cmd` you can pattern-match, no new instrumentation needed if you're willing to tail/parse the journal.
     If instead you want synchronous, structural bookkeeping (not journal-parsing), the same `journal(_:)`
     call site (:407) is where to ALSO update a new onboarding store, since every mutating command already
     funnels through it.
   - `"action"` — `agterm/AppActions+Palette.swift:62` (palette-invoked command) and `:128` (keymap-invoked
     built-in action) — distinguishes `source: "palette"` vs `"keymap"`.
   - `"key"` — `agterm/Commands/CustomCommandRunner.swift:196` (raw chord telemetry).
   - `"state"` — pane-state flips: split on/off (`agtermCore/Sources/agtermCore/AppStore+Panes.swift:39`),
     scratch on/off (`AppStore+Panes.swift:391`), session closed (`agtermCore/Sources/agtermCore/AppStore.swift:389`).
   Dashboard-open, palette-open, and failover-handoff themselves are NOT separately journaled today (only
   the "action"/"control" commands that trigger them are) — see section 7 for their actual function names
   if per-feature discovery events are wanted instead of control-command pattern matching.

## 6. docs/ui-lexicon.md — vocabulary rules (10 lines)

- Every visible control has one canonical **token** (lowercase-hyphenated, e.g. `split-toggle`,
  `dashboard-toggle-button`) and a matching `accessibilityIdentifier` in code — feedback/bugs reference the
  token, never "the button top right".
- Hold ⌥ in the running app to reveal a live cheat-sheet overlay of every ON-SCREEN control (icon · token ·
  shortcut); hidden-via-Settings controls don't appear in it.
- Feedback format is machine-parseable: `<id> · <state?> : <did X> → expected Y, got Z`.
- Multi-state controls (`split-toggle`, `focus-filter-toggle`, `flagged-view-toggle`, `scratch-toggle`) name
  their state explicitly; `split-toggle` in particular is 3-state (`none`/`both`/`left`|`right`|`top`|`bottom`),
  not a binary toggle — see `:66-88`.
  Terminology distinguishes "накрывашки" (overlay layers: quick terminal + dashboard cover the WINDOW,
  scratch covers the SESSION, zoom covers the PANE) with an explicit z-order/precedence rule (`:63-64`).
- Ground truth for live state is always `agtermctl tree --json`, never eyeballing — the doc tells contributors
  to check there before guessing a control's current state.
- Sidebar rows are addressed by name ("workspace mars", "session ✳ Claude Code") or id from the tree, not by
  position.

## 7. Dispatch sites: spawn / reader / run / dashboard / palette / failover

- **`agx spawn` / `agx reader` / `agx run` / `agx schedule` / `agx context` / `agx usage`** are a separate
  **Python** CLI (`scripts/agx`, sugar over `agtermctl` — NOT Swift), dispatched by a flat `if cmd ==
  "spawn": return cmd_spawn(argv)` chain at `scripts/agx:636-652` (`cmd_spawn` :403, `cmd_run` :539,
  `cmd_reader` :597, `cmd_usage` :482; `schedule` just shells out: `subprocess.call([CTL, "schedule",
  *argv[2:]])` :638). `agx spawn`'s Swift-side landing is the `session.*`/agent-launch control commands
  (see `SessionCommands.swift`, `Session: ParsableCommand` subcommands at
  `agtermCore/Sources/agtermctlKit/SessionCommands.swift:15-19` — `New`, `Duplicate`, etc.).
- **`agx reader`** Swift-side: `ControlDispatcher+Reader.swift` / `ControlServer+Reader.swift` (command
  `session.reader`, per `scripts/agx:614` `[CTL, "session", "reader", *verb]`).
- **`dashboard`**: `DashboardController` (`agtermCore/Sources/agtermCore/DashboardController.swift`) —
  `open(members:highlighted:)` (:82), `close()` (:94), `highlight(_:)` (:104), `move(_:)` (:121),
  `promoteSplitMember(session:)` (:142). Multiple controllers registered per window
  (`register(_:controller:)` :181 / `unregister` :185 / `controller(for:)` :189).
- **`palette`**: `PaletteController` (`agterm/Views/Palette.swift:78`), items are `PaletteItem`
  (`:7`); invocation logs via `AppActions+Palette.swift:62` (see section 5's `"action"`/`"palette"` journal
  entry) — that IS the palette's dispatch/telemetry point.
- **`failover`**: `AgentFailoverCoordinator` (`agterm/AgentFailoverCoordinator.swift:12`), the actual handoff
  function is `private func handoff(_ session:store:agent:reason:...)` at `:142`.

These five are the natural per-feature "discovered" hooks if the onboarding tracker wants semantic events
(`"used dashboard"`, `"used palette"`, `"got a failover handoff"`) rather than just pattern-matching the
`"control"` journal `cmd` field from section 5.
