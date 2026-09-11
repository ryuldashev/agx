# 2026-09-12 — onboarding: Welcome panel with live checks, discovery map, Help ▸ Getting Started…

Branch `onboarding-2026-09-12` off `26c9fd4` (the deployed v0.24.0, agent-profiles tip; `origin/master`
is ~10 commits behind and lacks reader/failover/profiles, so basing there would revert them on deploy).
Plan and every "decided alone" call: `docs/plans/onboarding.md` (§4). Research inputs:
`docs/plans/research/{personal-layer,installers-audit,ui-patterns}.md`.

## What
- `WelcomeAlert` (NSAlert with Install hooks/skill checkboxes) is gone. First launch and Help ▸ Getting
  Started… open one non-modal `WelcomeWindow`: a setup checklist whose rows are READ from the system every
  2 s (notification authorization, Accessibility/Screen Recording/FDA probes, `/usr/local/bin` symlinks
  pointing into this bundle, hook markers per agent via `AgentHooksInstaller.status()`, skill marker on
  disk, connected agents in settings), six "first moves", and "Discovered N of 12" with what is still to
  try. Each pending row's button does the one thing that flips it (the existing installers, the
  permission wall, Settings ▸ Agents).
- Discovery map: `DiscoveryTracker` observes `ActionJournal` (new `setObserver`) and keeps the first
  time of each capability in `<state>/discoveries.json`. New journal signals for it: `dashboard=on`,
  `hints=on` (⌥ held), `failover=handoff`, `via=agx-spawn` on `session.new` (the `agx-brief-` temp file).
- `agx context` MANIFEST: "close MY OWN session" line — «закрой сессию» means this pane, not a handoff.
- The permission wall no longer chains after the welcome on first launch; the panel's Permissions row is
  its entry. Upgraders (welcome shown, primer not) keep the old wall.

## Verified
`swift test` 2793/2793 (10 new in `OnboardingTests`), `make test-app` 261/261, `make lint` clean,
Release build. By hand on an isolated Debug instance (`AGTERM_STATE_DIR=/tmp/agxob`): panel opens on
first launch, rows read the real system, `session split` / `reader open` / `status` / `quick` over the
isolated socket light 4 of 12 live. The panel is clamped to the screen height and scrolls.

## Not verified
- Install…/Allow…/Review… buttons were not pressed from the Debug instance (they write `~/.claude`,
  `~/.config/agx`; CLAUDE.md forbids it from a worktree build) — press them from the deployed Release.
- `WelcomeUITests` (rewritten for the window) could not run: XCUITest "Timed out while enabling
  automation mode" from this session; needs a run from Ruslan's GUI session.
- A live `agx spawn` → `via=agx-spawn` → "Spawn" row green: matcher unit-tested only.

## Next
- `Bash(agx:*)` permissions hint with Copy on the hooks row (plan §1/§4).
- Uninstall/Revert for hooks, skill and CLI (plan §2 backlog); `ghostty.conf shell-integration-features`
  default bug.
- `onboarding.status` control command + read-back once the panel settles.
- Bundle the guide so "Open Guide" stops pointing at GitHub.
