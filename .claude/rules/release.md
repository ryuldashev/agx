---
paths:
  - "scripts/release.sh"
---

## Release (`scripts/release.sh`)

- **Releases are local; there is no `release.yml`.** Run `scripts/release.sh <version> --publish` on the
  maintainer's Mac, which holds the `Developer ID Application: Brave Elk LLC` certificate and
  `agterm-notary` keychain profile. The script builds Release, signs/notarizes/staples the app and DMG,
  creates the tag and GitHub release, uploads the DMG, then pushes the Homebrew cask to
  `umputun/homebrew-apps` using the maintainer's `gh` auth. It needs no `HOMEBREW_TAP_PAT`. The DMG
  container must be codesigned before notarization or `spctl` rejects `hdiutil`'s unsigned image.
  Without `--publish`, the full build/sign/notarize/staple/`spctl` dry-run stops before upload.
- Before writing or committing a release section, put the exact `CHANGELOG.md` text in a temp file and
  pass it through the `draft-approval` skill's `draft-review.sh`; address annotations and get explicit
  chat approval. `release.sh:70-85` publishes that text as the GitHub release body.
- **Commit and push the changelog and website version to `master` before `release.sh --publish`.**
  `gh release create "$TAG"` has no `--target` (`release.sh:166`), so it tags `origin/master`, not local
  `HEAD`. The script pushes only its cloned Homebrew tap; the maintainer must push the main repo.
- Manually set `site/index.html`'s `SoftwareApplication.softwareVersion` in that same pre-release push;
  `release.sh` does not edit it. Cloudflare Pages deploys `site/` on push, and the DMG links already use
  GitHub's latest release.
- **Auto-update rides on the release (ADR 0004).** `release.sh` EdDSA-signs the DMG with the keychain item
  `agx` (`sign_update --account agx`; the Sparkle tools sit in
  `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin` after the build) and uploads the one-item
  `build/appcast.xml` beside it; the app's `SUFeedURL` is GitHub's `releases/latest/download/appcast.xml`
  redirect, so the newest non-prerelease release IS the feed. Never upload a DMG by hand — without the
  matching appcast and signature it is invisible or refused to the updater. Never publish a broken build
  as a plain release: `--prerelease` keeps it out of `releases/latest`. The key's backup is
  `~/.secrets/agx-sparkle-ed25519.key`; a lost key means a new `SPARKLE_PUBLIC_ED_KEY` and a fleet that
  must reinstall by hand once.
- The CHANGELOG section for the version is also the in-app release notes (rendered through
  `gh api markdown`), so write it for the person clicking "Install and Relaunch", not for git log.
