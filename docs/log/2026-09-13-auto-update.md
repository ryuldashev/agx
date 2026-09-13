# 2026-09-13 — auto-update (Sparkle, `update.*`, signed appcast on the release)

Branch `worktree-auto-update-2026-09-13` off `agent-failover-2026-09-11` (itself unmerged, on top of
`reader-pane-2026-09-10`). ADR: `docs/decisions/0003-sparkle-auto-update.md`. Rule text:
`.claude/rules/release.md` (appcast + key), `.claude/rules/control-api.md` (catalog line).

## What
Installs from v0.25.0 on update themselves: Sparkle 2.9.6 checks the appcast attached to the latest
GitHub release once a day (and on agx ▸ Check for Updates…), verifies EdDSA + Developer ID, swaps the
bundle and relaunches; durable panes reattach, so no agent loses context. The whole rollout is
`scripts/release.sh X.Y.Z --publish`, which signs the DMG for Sparkle and uploads `appcast.xml` next to it.

## Built
- **project**: Sparkle via SwiftPM (`exactVersion: 2.9.6`), `SPARKLE_PUBLIC_ED_KEY` build setting,
  Info.plist `SUFeedURL` (`releases/latest/download/appcast.xml`), `SUPublicEDKey`,
  `SUEnableAutomaticChecks`, `SUScheduledCheckInterval` 86400. Homebrew cask `auto_updates true`.
- **agtermCore** `AppUpdate.swift`: `AppUpdateState`, `AppUpdatePolicy` (gates: `0.0.0`/`unknown`
  version, Debug, `AGTERM_STATE_DIR`, hosted/UI tests, `AGX_NO_UPDATE=1`; `AGX_UPDATE_FEED=<url>`
  staging override), `ControlUpdateNode` + `humanDescription`. `Command.updateCheck/Status/Install`,
  `ControlResult.update`, `ControlTree.update`, events `update.available`/`update.installing` (+
  payload `version`), `ControlActions.update*`.
- **agtermctlKit**: `UpdateCommands.swift` (`update check|status|install`), human read-back, events line.
- **app**: `AppUpdater.swift` (`SPUStandardUpdaterController` + delegate mirroring state into the node
  and ring; `updaterWillRelaunchApplication` sets `AppDelegate.isRestarting`),
  `Control/ControlServer+Update.swift`, `AppActions.updater`, scene-task wiring, menu item under About.
- **release**: `release.sh` signs Sparkle's nested helpers inside-out before the framework (notarization
  needs it), runs `sign_update --account agx`, renders the CHANGELOG section through GitHub's markdown
  API into the appcast `<description>`, `xmllint`s it, uploads DMG + appcast with `--clobber`.
- **Tests**: `AppUpdateTests`, `ControlDispatcherUpdateTests`, `UpdateCommandsTests`, protocol
  every-kind event test. Docs: ADR 0003, `FORK.md`, `site/commands.html#update`, skill reference/SKILL,
  `scripts/agx` context line, `CHANGELOG.md` `v0.25.0 - unreleased` draft.

## Verified
E2E on an isolated instance: Release build stamped 0.24.0 + `AGX_UPDATE_FEED=http://127.0.0.1:8765/
appcast.xml` (fake 0.25.0 DMG, Developer ID, `sign_update`) → `update check` → `available: 0.25.0`,
`tree.update`, `agx context` line → `update install` → `ready` → quit → bundle on disk is 0.25.0 and
`codesign --verify --deep --strict` passes → relaunch says `up to date`. "Install and Relaunch" (the
in-dialog click) was not exercised. `file://` feeds fail in Sparkle's downloader — use loopback HTTP.

## Not done / next
- EdDSA key: keychain item `agx` on this Mac, backup `~/.secrets/agx-sparkle-ed25519.key` (0600). No
  copy elsewhere yet — losing both strands every install on a key the app no longer trusts.
- Before `release.sh 0.25.0 --publish`: bump plugin manifests to 0.25.0, date the CHANGELOG section,
  `site/index.html softwareVersion`; a `release.sh 0.25.0` dry run proves the nested Sparkle signing
  notarizes. Ruslan reviews the CHANGELOG text first.
- v0.24.0 installs (the first users) have no Sparkle; they install 0.25.0 by hand once.
- The About menu item still reads "About Agterm" — untouched, out of scope.
