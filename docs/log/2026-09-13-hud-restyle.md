# 2026-09-13 — HUD restyle: no backing, notice-like typography, soft fade

Branch `agent-failover-2026-09-11`, base `6e54dc1` (glass HUD, deployed, app not yet relaunched).

## Goal
HUD without a plate: text alone at the pane's top edge, macOS-notice typography, soft fade+drift
(Reduce Motion → fade only, Reduce Transparency → keep readable). Text must read on wallpaper and on
a dark terminal (shadow/outline).

## Status
- [ ] design pass (design-squad: impeccable + emil-design-eng)
- [ ] code
- [ ] build / test / lint
- [ ] commit / deploy
- [ ] shown live, feedback

## Notes

### Decision (11:xx)
The HUD text was painted by `hud.sh` inside a ghostty surface (monospace, no shadow possible, plate
needed for contrast). A macOS-notice look is not reachable that way, so the HUD renders NATIVELY now:
`HudNoticeView` (SwiftUI `Text`, SF 13pt semibold + 11pt secondary detail, text shadows, no plate unless
`--background-color`), placed by `HudPosition` alignment with a fixed 12pt inset. The helper pipeline
(hud.sh, body file, `AGTERM_HUD_FILE`, `renderedBody`/`paintGrid`, `hudOverlayText`) goes away.
Protocol, CLI, read-back (`size_percent` = width budget, position, text/background color, spinner) stay.
Motion: enter 220ms strong ease-out (opacity + 6pt drift + 0.98 scale), exit 160ms; Reduce Motion → fade
only, both ways. Spinner frames cycle via `TimelineView` at `HudSpinner.interval`.
- agtermCore done: `openHud(_:spec:size:)`, `Session.discardHud()`, `HudSpinner.interval: Double`, frames public,
  helper rendering (`renderedBody`/`paintGrid`/`foregroundSGR`/`fileEnvKey`), `hudOverlayText`, `writeFailed`
  removed; HudHelperTests deleted. `swift test`: 2729 passed.
- App side done: `HudNoticeView` (new), deck renders it in place of the overlay TerminalView when `hudActive`;
  `OverlayPanelStyle` lost glass/HUD chrome/offset math (`sizeFraction` + `HudPosition.alignment`);
  hud.sh + project.yml resource removed; surface factory/GhosttySurfaceView HUD hooks removed. `make build` OK.
- Gates: `make build` OK, `swift test` 2729 pass, `make test-app` 248 pass, `make lint` clean.
  Docs synced: site/commands.html, skill SKILL.md/reference.md, .claude/rules/control-api.md.
