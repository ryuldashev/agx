#!/usr/bin/env bash
# Build a release app.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/setup.sh
xcodegen generate
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
# version = latest reachable v-tag (About panel / CFBundleShortVersionString);
# builds past the tag keep its version and the GitCommit parenthetical
# disambiguates. Falls back to 0.0.0 when no tag is reachable (shallow CI).
# `|| true` inside the substitution: `git describe` exits 128 with no tags, which
# under `set -e` would abort before the fallback below — swallow it so the empty
# result reaches the `-n` check.
VERSION="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)"
[ -n "$VERSION" ] || VERSION="0.0.0"
# Signing identity for the LOCAL release build (scripts/release.sh signs its own, authoritatively).
# macOS binds every TCC permission grant to the app's designated requirement; for an ad-hoc signature
# that requirement is the cdhash, so each rebuild is a brand-new app to TCC and every permission the
# tools running in panes use — media library, Photos, Downloads — gets asked for again. A Developer ID
# signature makes the requirement `identifier + team`, which survives rebuilds. Ad-hoc stays the
# fallback so a machine without the certificate still builds.
SIGN_ID="${AGTERM_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}' || true)"
fi
if [ -n "$SIGN_ID" ]; then
  echo "signing identity: $SIGN_ID"
else
  SIGN_ID="-"
  echo "WARNING: no Developer ID Application identity — signing AD-HOC; macOS will re-ask for permissions after every rebuild"
fi
xcodebuild -project agterm.xcodeproj -scheme agterm -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" GIT_COMMIT="$GIT_COMMIT" build
echo "built: build/DerivedData/Build/Products/Release/agx.app"
