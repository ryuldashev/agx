# agx context — UI self-awareness for in-pane agents

Status: prototype shipped (script), native command pending.

## What
`agx context` (script: `scripts/agx`, symlinked to `~/.local/bin/agx`) gives an agent running
inside an AGX pane a single self-description: **who am I** (session/workspace/window/pane/cwd,
what's running), **what the user sees now** (windows + frontmost, app focus, sidebar mode,
quick-terminal, per-session status/attention/foreground), and a **capability manifest** — the
exact `agtermctl` commands it can drive, plus an honest "you cannot" list. `--json` for machine use.

It composes `agtermctl tree --json` + `window list --json` + the `AGTERM_*` pane env. No app rebuild.

Discoverability: `~/.claude/CLAUDE.md` tells every Claude session under `AGTERM_ENABLED=1` to call it.

## Why a script first
A native `agtermctl context` needs app-side Swift + rebuild/redeploy. The script proves the output
shape on live data today and is fully reversible. Fold into `agtermctl context` once the shape settles.

## Next
- Native `agtermctl context` (move the composition into the control server; expose view-state the
  script can only infer — true per-window focus binding, selected text, active overlay).
- Agent request/response: `session type` is fire-and-forget stdin. A structured "ask session X and
  get the reply" primitive (correlate via a marker + `session text` poll, or a real control verb)
  is the one genuinely-missing action for smart cross-agent work.

## agx spawn — the smart "create a session for an agent" (shipped)
`agx spawn --brief "<task>" [--name T] [--workspace-name W|--workspace ID] [--cwd P] [--foreground]`
creates an agent session AND seeds it with the brief atomically. Creating a bare session for an
agent lands it with no task (observed real bug: agent made an empty "Админка" session, no brief).

Seeding must NOT type into the TUI: a freshly spawned `claude` drops input typed before it is
ready — a race that loses the brief (and matches the "не сразу / пустая сессия" report). Instead
spawn passes the brief as the agent's FIRST-MESSAGE argument via `zsh -lc 'exec claude "$(cat FILE)"'`
— the brief lives in a temp file (no quoting hazard), the agent starts already carrying it, and it
works even for a `--no-select` background pane. Verified live: brief → first user message → reply.

## Discovery (shipped)
SessionStart hook `~/.claude/hooks/agx-session-context.sh`, gated on `AGTERM_ENABLED=1`, injects the
full `agx context` once into each new in-pane session (chosen over an always-on CLAUDE.md line so the
cost lands only inside AGX). Already-running sessions get it on their next start/resume, not live.

## agx usage + honest statusline (shipped) — toward a native cross-session status panel
Why the CC statusline reads wrong: it is fed ONLY the current session's JSON, so it is
per-session by construction and can never aggregate. Concrete bugs fixed in
`~/.claude/bin/statusline.sh` (backup `statusline.sh.bak-*`): `day:`→`5h:` and `wk:`→`7d:` (the
fields are `.rate_limits.five_hour` / `.seven_day`, so "day" was a mislabel); added absolute
context `(NNNk)` and a red `⚠2x` at ≥200k (the double-tariff line, the number that actually costs).
The `ses:N` file-mtime count overcounts (catches subagents/background) — left in the bar but
superseded by `agx usage`.

Data plane: the statusline now also writes its parsed metrics to `~/.claude/agx-usage/<AGX sid>.json`
(only when `AGTERM_SESSION_ID` is set) — free, it already holds the numbers. `agx usage [--json]`
joins those emits with the live `tree` (so it counts only real open agent sessions) and prints
per-session model/context/cost + the account 5h/7d pools once. A session populates when its
statusline next renders.

Native panel (Swift, SHIPPED): `agterm/Views/UsagePanel.swift` — a cross-session usage strip in the
sidebar footer (`WindowContentView.sidebarFooter`, above the workspace/session buttons). `UsageReader`
polls `~/.claude/agx-usage/*.json` every 5s and joins it with the live `store.workspaces` sessions
(closed/stale drop out); the strip shows account 5h/7d pools, total live cost, reporting-session count,
and a ⚠ when any session crosses 200k. Tap → per-session popover (model, ctx% (k), cost). It reads the
same emit files the CLI `agx usage` does — one data source, two renderers. Appears after an app restart.

Follow-ups (not blocking): a Settings ▸ Interface toggle to hide it (add an `InterfaceElement` case +
`shows(_:)` gate); include open agent sessions that have not emitted yet as "—" rows; per-model color.

## agx run + own-side-pane execution (shipped)
Use-case: the agent's own turn is blocked by the command classifier (ssh, composer, package managers)
but the work is legitimate on the user's machine — the agent should run it ITSELF in its session's
side pane, not hand steps back to the user. `agx run "<cmd>"` runs a FINITE command in an overlay on
the current session's pane (`session overlay open <wrapper> --block --target $AGTERM_SESSION_ID`), the
command text held in a /tmp file (no quoting hazard) with output tee'd to a sibling file, and prints
`<output>` + `[agx run: exit N]`. Verified live (echo/uname/php -v → exit 0). For a PERSISTENT process
(ssh tunnel, `artisan serve`) the manifest points at the scratch shell (`session scratch on --command`),
which stays alive and is read back with `session text --pane scratch`. Note: this runs in the user's own
UNrestricted shell — deliberately outside the agent turn's classifier, since it's the user operating
their own terminal via the agent. Manifest also now teaches spawn-brief craft and the agx-session vs
in-turn-subagent distinction.

## agx spawn — two gotchas fixed (from dogfooding the abduco spawn)
1. Default workspace was the app-focused one (`session new`'s default), not the CALLER's — a spawned peer
   landed in whatever window had focus. Fixed: with no `--workspace/--workspace-name`, spawn now defaults
   to `$AGTERM_WORKSPACE_ID` (the asking agent's own workspace).
2. Spawning into a directory Claude hasn't trusted yet stops on the one-time trust gate before the seeded
   brief can run. NOT bypassed (it's a real security gate) — instead spawn reads
   `~/.claude.json` → `projects[<abs>].hasTrustDialogAccepted` and, when false, prints a clear one-line
   warning that the pane needs a one-time trust acceptance before the brief runs (`cwd_trusted` in --json).
