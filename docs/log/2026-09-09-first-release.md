# 2026-09-09 — first packaged release (v0.24.0), product page, Fred E2E

Goal: agx usable by other people (Mars devs), not only from this Mac.

## Done
- `scripts/release.sh` is the fork's: `agx-<v>.dmg`, volname `agx`, cask `packaging/agx.rb` seeded
  into `ryuldashev/homebrew-agx` (tap created; the script skips the cask bump if the tap is missing).
- Notarization: the vendored `abduco` is a nested Mach-O and the notary service rejects the archive
  unless it is Developer ID-signed with hardened runtime + timestamp — the script now signs it before
  the app. Auth also works from the environment (`AGTERM_NOTARY_KEY/KEY_ID/ISSUER`), since a
  sandboxed shell may not see the `agterm-notary` keychain profile.
- `ship-agx-cli-hooks-2026-09-09` merged: `scripts/agx` bundled at `Contents/Resources/agx`,
  Help ▸ Install Command Line Tool links `agtermctl` and `agx`, Help ▸ Install Agent Status Hooks adds
  the two Claude Code `SessionStart` hooks (UI context, session restore).
- Product page `site/index.html` (agx, not upstream's), live at https://agx.marshub.uz
  (marshub pages: `sites/agx/releases/1`, row in `sites`). Docs/Commands pages stay upstream's.
- Plugin manifests bumped to 0.24.0; CHANGELOG has the `v0.24.0` section the release notes are cut from.
- DMG built, signed, notarized (app + DMG accepted, stapled).

## E2E on Fred (second Mac, macOS 15.5, no brew, no prior agx)
- DMG and app assess as "Notarized Developer ID"; bundled `agx` parses under python 3.9.
- Blocked at the first GUI step: Fred's screen is locked (`CGSSessionScreenIsLocked=Yes`), no Screen
  Sharing, no passwordless sudo. Every launch — the app, `agtermctl tree`, even `agx --help` via
  `/usr/bin/env` — parks in `_dyld_start`: syspolicyd's first-launch assessment waits on a dialog the
  locked screen cannot show. Resume the GUI onboarding (welcome, permissions wall, three Help ▸ Install
  items, Settings ▸ Agents ▸ Connect, workspace defaults, spawn, relaunch reattach) once unlocked.
- Copying the quarantined app with `cp` (or running it from the DMG) launches it from an App
  Translocation path; the installers would bake that random path. Finder drag / brew avoid it; the
  product page now says so.

## Next
- Finish the Fred onboarding pass; UI scripting from ssh needs Accessibility for `sshd-keygen-wrapper`.
- Consider control-API twins for the three Help ▸ Install actions so onboarding is scriptable
  (provisioning a fleet of Macs without clicking). Fits the "every feature reachable through the API" norm.
- `site/docs.html` / `commands.html` / `llms.txt` still say agterm + umputun cask.
