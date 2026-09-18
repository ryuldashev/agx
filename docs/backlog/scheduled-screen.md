# Scheduled screen — the schedule queue without the CLI

Status: TODO, not started. Asked by Ruslan 2026-09-18 after parking 9 sessions:
`agx schedule list` is the only view of the queue; it needs a window like Artifacts (⇧⌘A).

## Why now
Parking (close a stuck session → handoff file → `schedule add` → reopen with the brief as first
message) only works if the parked queue stays visible. Today 15 jobs sit in `scheduled.json`
with no UI: nothing shows that 7 open at once tomorrow 09:00, and a `missed` job is invisible
until someone runs the CLI. Handoffs of the first batch live in `~/mars/parked/` (`INDEX.md`).

## v1 scope
Reuse the Artifacts window pattern (`agterm/Views/ArtifactsWindow.swift`, `AppActions+Artifacts.swift`):
- Table: when (absolute + relative), workspace, name, state (`pending` / `missed`; missed on top).
  Live via `schedule.added/.fired/.cancelled/.missed` events.
- Actions, no dialogs: Run now (⏎), Cancel (⌫; brief goes to the log first, never lost),
  +1 hour, +1 day, Show brief (reader pane).
- Entry points: View ▸ Scheduled, palette, `agtermctl schedule show`. ⇧⌘S is taken (Студия) —
  pick a free chord via `keymap list`.
- Data and protocol already exist (`ControlServer+Schedule.swift`, `schedule list/cancel/run`);
  a reschedule needs one new command (`schedule move <id> --at`), with CLI, dispatcher and tests.

## Not in v1
Editing the brief, creating jobs from the window, day grouping, calendar view.

## Follow-up idea: `agx park`
One command = brief from the transcript (`AgentFailover` already builds one) + `schedule add`
+ `session close`. Build only after the manual parking ritual survives a week.
