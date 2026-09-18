# 2026-09-18 — Artifacts screen (View ▸ Artifacts, ⌘⇧A, `artifact.*`)

Plan: `docs/plans/artifacts-screen.md` (data-source decision evidenced from real transcripts).
Branch `worktree-artifacts-2026-09-18` off `origin/master` 4e71900.

## What shipped

- **Core** `agtermCore/Artifact.swift`: `Artifact`, `ArtifactIndex` (dedup by normalized key, pinned-first
  filtering, prune at 2000 keeping pinned), `ArtifactPolicy.normalize` (the one key rule), `ArtifactStore`
  (`<stateDir>/artifacts.json` v1, atomic), `ArtifactLibrary` (`@Observable`), `ControlArtifactNode`.
  `ControlDispatcher+Artifact.swift` validates; 7 `artifact.*` commands; `artifact.added` event.
- **App** `ControlServer+Artifact.swift` (session names frozen at record time, `ArtifactOpener` = the only
  `NSWorkspace` caller), `Views/ArtifactsWindow.swift` (app-global `NSWindow` + SwiftUI `Table`, filters,
  context menu, Quick Look, ⌘C/Return/Space/Delete), `show_artifacts` builtin (⌘⇧A), View menu, palette.
- **CLI** `agtermctl artifact add|list|remove|pin|hide|open|show`; `agx artifact …` wrapper and
  `agx artifact backfill [--days N|--all] [--dry-run]` inside `scripts/agx` (single bundled file, no
  second script — the plan's `agx-artifacts-backfill.py` was folded in).
- **Hook** `Resources/agent-status/agx-artifacts.sh`, `PostToolUse` with matcher `Bash|SendUserFile`, added
  to `AgentHooksInstall.claudeHooks` and the installer's bake list. Bash prefilter, python3 parse with
  `shlex(punctuation_chars=True)` so `;`/`&&`/`|`/redirections split correctly; `cd … &&` prefixes move
  the base; `open -a App` / `-R` flag values excluded; directories skipped.
- **Docs**: reference.md + SKILL.md (skill), control-api.md (catalog + section), site/commands.html
  (`#artifact`), site/docs.html (`#artifacts`, builtin catalog), FORK.md.

## Verified

- Isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agxart`): add/dedup/pin/hide/remove/open/show over the
  socket; window on screen (960×592, title "Artifacts"); hook driven with 7 payloads (4 PDFs via
  `cd doc && open a b && open -a Preview c; open -R d`, URLs, `agx reader --title`, SendUserFile with
  caption; `ls`/`Write`/garbage are no-ops); backfill `--days 3` recorded 45 rows, `pitch.pdf` maps to
  session `44431C01` (the "Оценка v2" pane) via `restoreCommand`, and an older backfill did not override
  the live row.
- Gates: `make build`, `swift test` (35 new artifact tests + pins), `make lint` zero findings,
  `agtermUITests/ControlArtifactUITests` (2 tests) — one launch flake ("has not loaded accessibility",
  FB11763863) passed on rerun. `make test-app`: see commit.
- 30-day dry run over the real transcripts: 1087 files scanned, 301 artifacts, 40 transcripts map to an
  open/recent session.

## Deviations from the plan

- `artifact.add` returns no `affected` (the CLI's `affected` formatter would print "1 session" before the
  id); dedup shows as the node's `count`.
- `ArtifactLibrary.setPinned/setHidden/remove` are `@discardableResult`.
- Default chord ⌘⇧A collided with a keymap test fixture that assumed the chord was free; the fixture now
  uses ⌘⇧Y.

## Next

- After Ruslan relaunches: Help ▸ Install Agent Status Hooks (from the deployed Release, so the baked
  `agtermctl` path is right), then `agx artifact backfill` once. Check ⌘⇧A shows `pitch.pdf` with the
  "Оценка v2" session and double-click opens Preview.
- Codex/Hermes sessions have no tool hook: only `agx artifact add` covers them (plan's non-goal).
- Backfill maps a transcript only to the pane that resumes THAT uuid; a pre-fork transcript of the same
  pane records without a session (cwd + transcript id still there).
