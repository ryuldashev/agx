# 2026-09-12 — Integration: guide + shortcuts sheet + onboarding

Branch `integration-2026-09-12` (worktree `.claude/worktrees/integration-2026-09-12`), built from
`guide-2026-09-12` (212db72, which already carries reader-pane → failover → agent-profiles) and merged:

- `shortcuts-sheet-2026-09-12` (b2b04c5) — Help ▸ Keyboard Shortcuts…, `ShortcutsSheet.swift`,
  palette command `keyboardShortcuts`. One conflict in `agtermApp+Menus.swift` (Help block), resolved
  by keeping both entries.
- `onboarding-2026-09-12` (0bd1355) — Welcome panel with live setup checks + discovery map,
  Help ▸ Getting Started…. Clean merge.

Post-merge fixes: palette static count 51→52 (each branch had bumped it independently);
"Getting Started…" moved to the first Help item (was below the installers).

Gates: `make build` ok, `make test` 2800/2800, `make lint` clean. `make deploy` → /Applications/agx.app
(0.24.0). Deployed at 01:4x; running instance still on the old bundle until Ruslan relaunches.

## Not done / for Ruslan

- `agtermctl app relaunch` — his action. After relaunch: Help menu should read Getting Started… /
  agx Guide… / Keyboard Shortcuts… / … / Permissions….
- Onboarding Install…/Allow…/Review… buttons untested from a Release build (see
  `2026-09-12-onboarding.md`); WelcomeUITests need a GUI-session XCUITest run.
- Guide: three screenshots still missing (Settings ▸ Agents, hooks result window, failover session).
  Read before anyone external sees it: `docs/guide/README.md`, `a-day.md`.
- `origin/master` (ddda9df) is far behind the whole dated chain — moving it is his call.
- The onboarding session had deployed its own branch first; this deploy supersedes it.

## Addendum 02:45
- Rebranded leftover "Agterm" strings (About item, quit prompt, window title) via `Brand.productName`; redeployed.
- `agx` workspace defaults set (`~/agterm`, Claude Code) — lost in the agterm+mmee merge. `mir`, `games`, `roblox`, `home` still have none.
- Four night sessions closed; their worktrees/branches kept for reference.
