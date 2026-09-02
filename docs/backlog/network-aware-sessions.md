# Network-aware sessions — offline/slow indicator and resume-after-recovery

Status: proposed 2026-09-02 (evidence gathered, nothing built).

## What
Agents in panes die silently when the laptop loses or degrades its uplink, and the user cannot tell
"slow network" from "agent hung" from "app broken". agx sees both the OS reachability and every
session's screen, so it can (1) show the network state, (2) mark which sessions are stalled by it,
and (3) once the uplink returns, nudge the sessions that ended a turn with a fatal API error.

## Evidence (2026-09-02, transcripts of the five affected sessions)
- Outage 15:26–15:47 UTC. Turns went silent for 5.5–12.3 min, then ended with a synthetic
  assistant message (`isApiErrorMessage:true`): `API Error: Connection lost mid-response` or
  `API Error: Connection dropped (ECONNRESET)`. Claude Code neither retries nor resumes; the user
  typed «продолжи» by hand in two sessions, seconds apart.
- A second, non-fatal class surfaces INSIDE the turn as an `is_error` tool result:
  `claude-sonnet-5[1m] is temporarily unavailable (connection failed), so auto mode cannot determine
  the safety of Bash` — the model sees it and can retry; the user sees nothing.
- Fail-fast variant (other days): `Can't reach the API server — check your internet or DNS (ENOTFOUND)`
  — seconds, not minutes. Slow/flaky is the hard case: a long silent hang, then ECONNRESET.
- Sub-agents stall the same way and are invisible from the pane (only the parent's screen shows).

## Design sketch
- **Signal A, OS:** `NWPathMonitor` in the app target → a host-free `NetworkState`
  (`online | constrained | offline`, with `since`) in `agtermCore`; transitions unit-tested.
- **Signal B, screen:** the pane's last lines (the `session text` capture the app already owns)
  matched against a small catalog: `API Error:`, `Connection lost mid-response`, `ECONNRESET`,
  `ENOTFOUND`, `temporarily unavailable`. Catalog lives in `agtermCore`, tested on the real strings
  above. A session whose status is `active` and whose screen is unchanged for >60 s while
  state ≠ online is "stalled by network"; one whose last line is a fatal `API Error:` is "dropped".
- **Surface:** tree top-level `network {status, since}`; per-session `stall: network|dropped`;
  event `network.changed` and `session.stalled`; sidebar glyph reuses the `blocked` status override
  with a network reason; a titlebar indicator only while not online (candidate for `InterfaceElement`
  — needs approval before adding the preference).
- **Action (opt-in, default off):** Settings ▸ General ▸ "Resume agents after the network returns":
  on `offline→online`, for every "dropped" session type the resume line (`continue\n` / «продолжи\n»
  per session language) exactly once, then emit `session.resumed`. Never type into a session whose
  last line is not the fatal marker — it may be at an interactive prompt.
- **Control API:** `agtermctl network` (read), `session.stalled` read-back, the setting via
  `settings`; dispatcher + CLI + protocol tests as for every action.

## Out of scope
Claude Code's own retry/backoff (upstream), stalls inside sub-agents (not visible from the pty).
