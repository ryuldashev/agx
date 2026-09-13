# 0003 — Auto-update: Sparkle, fed by the latest GitHub release

Status: accepted 2026-09-13 (Ruslan: "механику автообновления надо придумать и сделать — грамотно,
удобно, качественно, потому что первые юзеры появляются").

## Context

v0.24.0 went to the first outside users as a DMG and a Homebrew cask. Neither reaches them again: a
DMG user never hears about v0.25.0, and `brew upgrade` only helps the minority who installed through
the tap and remember to run it. Every fix from here on would otherwise ship into a fleet that stays
on whatever it first installed.

What shaped the design:

- The app is Developer ID-signed and notarized (`scripts/release.sh`), and the release is the DMG on
  a GitHub release. GitHub serves `releases/latest/download/<asset>` as a 302 to the newest
  non-prerelease asset, so a file uploaded beside the DMG is a stable URL with no hosting of its own.
- Durable panes (ADR 0001) make a relaunch cheap: every agent runs under abduco and reattaches with
  its context and unfinished turn. An update is therefore not "lose your 12 sessions", which is the
  usual reason terminal users postpone updates for weeks.
- A quit through `NSApp.terminate` raises the quit-confirmation alert; `AppActions.restartApp` already
  skips it through `AppDelegate.isRestarting`.
- Local builds (`make deploy`) carry the latest reachable tag as their version and Debug builds live
  in DerivedData under their own bundle id; XCUITest and hosted tests launch isolated instances.
  None of these may ever be offered, or replaced by, a release build.

Alternatives considered:

- **Homebrew only.** Already there; covers a subset, needs the user to act, and re-quarantines the
  bundle on every upgrade. Kept as a channel, not as the mechanism (`auto_updates true` tells brew
  the app updates itself).
- **A hand-rolled updater** (poll the GitHub API, download, swap the bundle, relaunch). Everything
  Sparkle already does — atomic replace of a running bundle, App Translocation, quarantine, signature
  verification, the "install on quit" path, the permission-prompt etiquette — would be re-learned bug
  by bug in front of the first users. Rejected.
- **Sparkle with an appcast on agx.marshub.uz.** A second deploy step per release (marshub pages) for
  a file that only changes when the release does. Rejected in favour of attaching it to the release.

## Decision

Sparkle 2 (SwiftPM, pinned `exactVersion`) drives the update; a one-item `appcast.xml` uploaded beside
the DMG by `scripts/release.sh` is the feed, read through
`https://github.com/ryuldashev/agx/releases/latest/download/appcast.xml` (`SUFeedURL`). The newest
published release IS the feed, so publishing a release is the whole rollout.

- **Signing.** Updates are EdDSA-signed (`sign_update --account agx` over the DMG; the public key is
  `SPARKLE_PUBLIC_ED_KEY` in `project.yml`, baked into `Info.plist` as `SUPublicEDKey`) on top of the
  Developer ID signature Sparkle also verifies. The private key is the `agx` item
  `generate_keys --account agx` created in the maintainer keychain, backed up outside the repository
  (`~/.secrets/agx-sparkle-ed25519.key`). Losing it strands every installed copy on its current
  version, since the baked public key would never match a new feed — the backup is not optional.
  `release.sh` signs Sparkle's nested helpers (`Installer.xpc`, `Downloader.xpc`, `Autoupdate`,
  `Updater.app`, then the framework) inside-out before the app, as the notary service requires.
- **Schedule.** `SUEnableAutomaticChecks` is set, so there is no first-launch "check automatically?"
  prompt; checks run once a day (`SUScheduledCheckInterval` 86400) and on `agx ▸ Check for Updates…`.
  Sparkle's standard dialog offers "Install and Relaunch", "Install on Quit", "Later"; release notes
  are the CHANGELOG section rendered through GitHub's markdown API at release time.
- **Relaunch.** `updaterWillRelaunchApplication` sets `AppDelegate.isRestarting`, so the install
  never stalls behind the quit alert and `applicationWillTerminate` still persists windows and restore
  commands. Panes reattach on the way back (ADR 0001).
- **Gate.** `AppUpdatePolicy.isEnabled` (host-free, tested) refuses to start the updater for a build
  whose version is `0.0.0`/`unknown`, a Debug build, an instance with `AGTERM_STATE_DIR` set, hosted
  or UI tests, and `AGX_NO_UPDATE=1`. A disabled updater never touches the network, is omitted from
  `tree`, greys out the menu item, and answers `update.*` with one error. `AGX_UPDATE_FEED=<url>`
  overrides the feed and lifts every gate but the opt-out, so a local build against a loopback HTTP
  appcast exercises the real download-verify-swap path before a release goes out.
- **Control API.** `update.check` (background check, no UI), `update.status`, `update.install` (the
  dialog); `result.update` and the tree's top-level `update` node
  `{version, state, available?, lastChecked?, automatic, error?}`; events `update.available` and
  `update.installing`. `agx context` appends "update X available" to its version line so an in-pane
  agent can tell the user, or install, without being asked.

## Consequences

- v0.24.0 installs do not have Sparkle; they learn about v0.25.0 the old way (product page, brew),
  once. Every install from v0.25.0 on updates itself.
- A release is now cut only by `release.sh`: the appcast, its signature and the DMG URL come from the
  same run, so a DMG uploaded by hand would be unsigned to the updater and refused. This is a feature.
- Pre-releases (`gh release create --prerelease`) are invisible to `releases/latest`, so a beta can be
  published without reaching the fleet; a beta channel would be a second feed URL, not done.
- The Sparkle framework adds ~2.5 MB to the bundle and one more nested-signature step to
  `release.sh`; `make deploy` builds keep working because the build-phase `--deep` re-sign covers the
  nested helpers and the policy keeps them from ever checking.
- Rebase risk on upstream: `project.yml` (package + dependency + key), `Info.plist`, `agtermApp.swift`
  wiring, the app menu; the rest is new files (`AppUpdater.swift`, `AppUpdate.swift`,
  `ControlServer+Update.swift`, `UpdateCommands.swift`).
