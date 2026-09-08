# 2026-09-09 — ship agx CLI + SessionStart hooks in the app

Goal: make agx installable for other users. Bundle `scripts/agx` in the app, link both
`agtermctl` and `agx` from Help ▸ Install Command Line Tool, and ship two Claude Code
SessionStart hooks (agx-session-context, agx-session-restore) via Help ▸ Install Agent Status Hooks.

Branch: `ship-agx-cli-hooks-2026-09-09` (worktree from origin/master 6c2efb2).

## Progress
- worktree created, GhosttyKit/stamp/resources symlinked from the main checkout
- `scripts/agx`: `CTL` now resolves `<dir of agx>/../MacOS/agtermctl` first (realpath, so the
  `/usr/local/bin/agx` symlink lands on the bundle), then PATH, then the Homebrew fallback.
- New hook scripts in `agterm/Resources/agent-status/`: `agx-session-context.sh`, `agx-session-restore.sh`.
  Both gated on `AGTERM_ENABLED=1`, python3 for JSON (no jq), silent, always exit 0. Smoke-tested with a
  stub agtermctl: restore passes `session restore "zsh -lc 'exec claude --resume <sid> --fork-session'"
  --target --pane --pane-id`; a non-id-shaped session_id is refused; garbage stdin is a no-op.
- `CLIInstall`: `Link`, `installPath(for:)`, `privilegedInstallCommand(links:)` (one `mkdir && ln && ln`),
  `describe(_:)` for the alert. `CLIInstaller` links agtermctl + agx, one admin prompt.
- `AgentHooksInstall.claudeHooks` carries the script per entry; two `SessionStart` entries (restore, then
  context); probe is per script path. Tests: 44/44 in AgentHooksInstallTests + CLIInstallTests.
- `AgentHooksInstaller.bakeAgtermctlPath` bakes per wrapper: AGTERMCTL into status/codex/restore,
  AGX into context. `ClaudeHook` struct replaces the 4-tuple (swiftlint large_tuple).
- `project.yml`: `scripts/agx` via a Copy Files phase (dstSubfolderSpec 7 = Resources), runs before the
  re-seal phase. Verified in the Release bundle: `Contents/Resources/agx` is 0755, the four hook scripts
  are 0755, `codesign --verify --deep --strict` passes, and the bundled agx resolves
  `Contents/MacOS/agtermctl` as its sibling (`agx context --json` from the bundle works).
- README Install: Homebrew `brew install --cask ryuldashev/agx/agx`, DMG from
  github.com/ryuldashev/agx/releases (drag agx.app), what the three Help ▸ Install items do.
  FORK.md: one paragraph under "What it adds".

## Gates (run once at the end)
- `cd agtermCore && swift test` — 2707 tests / 108 suites passed. (A first run tripped
  `RecentClosedControlTests.resolvesTheClosedSessionsOwnID` on a random UUID; it passes alone and on the
  re-run, and neither the test nor `RecentClosedResolve` is touched here — a pre-existing flake.)
- `make lint` — zero findings.
- `make release` — BUILD SUCCEEDED; the 7 warnings (abduco C, GhosttyApp, GhosttySurfaceView+Copy,
  appintents) are all pre-existing and outside the touched files.

## Not done / follow-ups
- `site/docs.html`, `site/index.html`, `site/llms.txt`, `docs/troubleshooting.md` still describe the
  single-tool install and the umputun cask (they are upstream's site surfaces); the README plugin
  marketplace lines still point at umputun/agterm. Left as is: only README + FORK.md were in scope.
- Hosted tests (`make test-app`) and XCUITests were not run, per the brief.
- The Homebrew cask `ryuldashev/agx/agx` is documented as the install path but not created here.
- Not merged to master, not deployed.

Done: bundled agx CLI + both symlinks from Help ▸ Install Command Line Tool + two SessionStart hooks
from Help ▸ Install Agent Status Hooks, tests, README/FORK docs; gates green.
Not done: site/docs/troubleshooting surfaces, cask creation, merge, deploy.
Branch: `ship-agx-cli-hooks-2026-09-09`.
