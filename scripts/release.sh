#!/usr/bin/env bash
# Build, sign, notarize, and package a release DMG locally, and (with --publish)
# upload it to a GitHub release and bump the Homebrew cask.
#
# Usage:
#   scripts/release.sh <version>            # build + sign + notarize + DMG (no publish)
#   scripts/release.sh <version> --publish  # also: gh release + cask bump/push
#
# Signing identity: auto-detected from the keychain ("Developer ID Application"),
# or override with AGTERM_SIGN_IDENTITY. With no identity it produces an AD-HOC
# DMG (not notarized) — a dry run by default, but set AGTERM_ALLOW_UNSIGNED=1 to
# --publish it as an unsigned release. Notary creds come from a keychain profile created
# with `xcrun notarytool store-credentials` (default name: agterm-notary,
# override with AGTERM_NOTARY_PROFILE). The Sparkle EdDSA key (ADR 0004) is the
# keychain item `generate_keys --account agx` created; `sign_update` reads it from
# there, and a backup lives outside the repository (see FORK.md).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"

VERSION="${1:-}"
PUBLISH=0
[ "${2:-}" = "--publish" ] && PUBLISH=1

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: scripts/release.sh <x.y.z> [--publish]" >&2
  exit 1
fi

TAG="v$VERSION"
DMG="$BUILD_DIR/agx-$VERSION.dmg"

# ── plugin manifest version ───────────────────────────────────────────────────
# The agent skill also ships as a Claude Code / Codex plugin, and both plugin
# managers key their install cache on the manifest "version" — an unbumped
# manifest means an existing install never picks up the new skill, silently.
# `gh release create` below runs with no --target, so the tag lands on whatever
# origin/master points at: the bump must be both COMMITTED and PUSHED, and both
# are checked here. This applies the bump and stops so the diff can be reviewed
# and committed, rather than rewriting git history from inside a release script.
PLUGIN_MANIFESTS=(
  "$ROOT/plugins/agterm/.claude-plugin/plugin.json"
  "$ROOT/plugins/agterm/.codex-plugin/plugin.json"
  "$ROOT/.claude-plugin/marketplace.json"
)
for manifest in "${PLUGIN_MANIFESTS[@]}"; do
  sed -i '' -E "s/(\"version\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$VERSION\"/" "$manifest"
done
# against HEAD, not the index — a bare `git diff` compares the worktree to the
# index, so a bump that was merely `git add`ed reads as clean and publishes stale.
if ! git diff --quiet HEAD -- "${PLUGIN_MANIFESTS[@]}"; then
  echo "==> bumped the plugin manifests to $VERSION — review and commit, then re-run:" >&2
  git --no-pager diff --stat HEAD -- "${PLUGIN_MANIFESTS[@]}" >&2
  exit 1
fi
# committed is not enough: the tag is cut from the remote, so verify the pushed
# manifests carry this version too.
if [ "$PUBLISH" = "1" ]; then
  git fetch -q origin master
  for manifest in "${PLUGIN_MANIFESTS[@]}"; do
    rel="${manifest#"$ROOT"/}"
    if ! git show "origin/master:$rel" 2>/dev/null | grep -q "\"version\"[[:space:]]*:[[:space:]]*\"$VERSION\""; then
      echo "==> $rel on origin/master is not at $VERSION — push master first" >&2
      exit 1
    fi
  done
fi
APP="$BUILD_DIR/DerivedData/Build/Products/Release/agx.app"
NOTARY_PROFILE="${AGTERM_NOTARY_PROFILE:-agterm-notary}"
# API-key auth (CI, or a shell whose keychain search list hides the profile) wins over the profile:
# AGTERM_NOTARY_KEY=<AuthKey.p8> AGTERM_NOTARY_KEY_ID=<id> AGTERM_NOTARY_ISSUER=<uuid>.
if [ -n "${AGTERM_NOTARY_KEY:-}" ]; then
  NOTARY_AUTH=(--key "$AGTERM_NOTARY_KEY" --key-id "$AGTERM_NOTARY_KEY_ID" --issuer "$AGTERM_NOTARY_ISSUER")
else
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi
TAP_REPO="ryuldashev/homebrew-agx"

# resolve the signing identity: explicit override, else the first Developer ID
# Application identity in the keychain, else ad-hoc dry-run.
SIGN_ID="${AGTERM_SIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
fi
if [ -n "$SIGN_ID" ]; then
  SIGNED=1
  echo "==> signing identity: $SIGN_ID"
else
  SIGNED=0
  echo "==> WARNING: no Developer ID Application identity found — building AD-HOC (dry-run, not notarized)"
fi

if [ "$PUBLISH" = "1" ] && [ "$SIGNED" = "0" ] && [ "${AGTERM_ALLOW_UNSIGNED:-0}" != "1" ]; then
  echo "refusing to --publish an ad-hoc (unsigned) build" >&2
  echo "set AGTERM_ALLOW_UNSIGNED=1 to publish the interim unsigned build (CI does this)" >&2
  exit 1
fi

# submit a path to the notary service and wait; fail loudly with the log on reject.
notarize() {
  local path="$1" json status id
  echo "==> notarizing $(basename "$path")"
  json="$(xcrun notarytool submit "$path" "${NOTARY_AUTH[@]}" --wait --output-format json)"
  status="$(printf '%s' "$json" | jq -r '.status')"
  id="$(printf '%s' "$json" | jq -r '.id')"
  if [ "$status" != "Accepted" ]; then
    echo "notarization failed: status=$status" >&2
    xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" || true
    exit 1
  fi
}

# build the GitHub release body: the matching CHANGELOG.md section followed by a
# short install note (signed + notarized; Apple Silicon only, macOS 14+).
release_notes() {
  local section
  section="$(awk -v ver="v$VERSION" '
    $0 ~ "^## " ver "( |$)" {grab=1; next}
    grab && /^## / {exit}
    grab {body[++n]=$0}
    END {
      s=1; while (s<=n && body[s] ~ /^[[:space:]]*$/) s++
      while (n>=s && body[n] ~ /^[[:space:]]*$/) n--
      for (i=s; i<=n; i++) print body[i]
    }
  ' "$ROOT/CHANGELOG.md")"
  [ -n "$section" ] || echo "WARNING: no CHANGELOG.md section for v$VERSION — release body will be the install note only" >&2
  [ -n "$section" ] && printf '%s\n\n' "$section"
  cat <<EOF
---

Signed with a Developer ID certificate and notarized by Apple, so macOS Gatekeeper opens it with no extra steps. Apple Silicon (arm64) only, macOS 14 or later.

- **Homebrew:** \`brew install --cask ryuldashev/agx/agx\`
- **Direct download:** open the \`.dmg\` and drag \`agx.app\` into \`/Applications\`.
- **Already installed:** agx checks for updates once a day and offers this one in-app (agx ▸ Check for Updates…).
EOF
}

# ── build ────────────────────────────────────────────────────────────────────
"$ROOT/scripts/setup.sh"
xcodegen generate >/dev/null
# plain Release build (NOT archive). The build is left ad-hoc here on purpose:
# Xcode's own final code-sign runs after the bundle phase and adds no secure
# timestamp, so trying to inject Developer ID at build time is racy. Instead we
# re-sign authoritatively below, AFTER xcodebuild returns.
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
xcodebuild -project agterm.xcodeproj -scheme agterm -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" GIT_COMMIT="$GIT_COMMIT" \
  build
[ -d "$APP" ] || { echo "expected app not found: $APP" >&2; exit 1; }

# authoritative Developer ID signing — AFTER xcodebuild so nothing clobbers it,
# with a secure --timestamp on every Mach-O (notarization requires it). Sign the
# nested helper first (inside-out), then re-sign + seal the app bundle. The helper is signed
# without --entitlements on purpose, and --deep must never be added to the app sign below:
# --deep would stamp the app's TCC entitlements onto agtermctl, a standalone CLI on the user's
# PATH. Same constraint as the build-phase re-seal in project.yml.
if [ "$SIGNED" = "1" ]; then
  echo "==> signing Developer ID (timestamped)"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/MacOS/agtermctl"
  # the vendored abduco session server is a nested Mach-O too (durable panes, FORK.md): the notary
  # service rejects the archive unless it carries the same Developer ID + hardened runtime + timestamp.
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP/Contents/Resources/abduco/abduco"
  # Sparkle (ADR 0004) ships its own helpers; each is a nested bundle the notary service checks on its
  # own, so they are signed inside-out per Sparkle's sandboxing guide. Downloader.xpc keeps the
  # network entitlement it was built with.
  SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
  codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_ID" \
    "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW/Versions/B/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW/Versions/B/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_FW"
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/agterm/agterm.entitlements" --sign "$SIGN_ID" "$APP"
  codesign --verify --deep --strict "$APP"
  if codesign -d --entitlements - "$APP/Contents/MacOS/agtermctl" 2>/dev/null | grep -q 'com.apple.security'; then
    echo "agtermctl carries entitlements: --deep must not be used on the app sign above" >&2
    exit 1
  fi
fi

# ── notarize + staple the app ─────────────────────────────────────────────────
if [ "$SIGNED" = "1" ]; then
  ZIP="$BUILD_DIR/agx-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vv --type execute "$APP"
fi

# ── package the DMG ───────────────────────────────────────────────────────────
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"; mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname agx -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

# ── sign + notarize + staple the DMG ──────────────────────────────────────────
# codesign the DMG container itself (create → sign → notarize → staple), so the
# primary-signature assessment below has a signature to verify. hdiutil produces
# an unsigned image; without this the DMG notarizes+staples but spctl rejects it.
if [ "$SIGNED" = "1" ]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vv -t open --context context:primary-signature "$DMG"
fi

echo "==> built: $DMG"

# ── appcast (ADR 0003) ────────────────────────────────────────────────────────
# One-item feed uploaded beside the DMG; the app reads it through GitHub's
# `releases/latest/download/appcast.xml` redirect, so the newest published release
# IS the feed and nothing else needs deploying. The EdDSA signature over the DMG is
# what the app verifies before installing (its public half is SPARKLE_PUBLIC_ED_KEY
# in project.yml); an unsigned dry run gets a feed with no signature and would be
# refused by a real install, which is the point.
APPCAST="$BUILD_DIR/appcast.xml"
SPARKLE_BIN="$BUILD_DIR/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
GH_ORIGIN="$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
ED_ATTRS=""
if [ "$SIGNED" = "1" ]; then
  ED_ATTRS="$("$SPARKLE_BIN/sign_update" --account agx "$DMG")"   # sparkle:edSignature="…" length="…"
  [ -n "$ED_ATTRS" ] || { echo "sign_update produced no signature (keychain item 'agx' missing?)" >&2; exit 1; }
fi
appcast_notes() {
  # the CHANGELOG section rendered by GitHub's markdown API, styled for Sparkle's notes pane
  local section html
  section="$(awk -v ver="v$VERSION" '$0 ~ "^## " ver "( |$)" {grab=1; next} grab && /^## / {exit} grab' "$ROOT/CHANGELOG.md")"
  html="$(gh api -X POST markdown -f mode=gfm -f text="$section" 2>/dev/null || printf '<pre>%s</pre>' "$section")"
  printf '<!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">'
  printf '<style>body{font:13px -apple-system,system-ui;padding:0 12px;line-height:1.45}h2,h3{font-size:14px}code{font-size:12px}</style>'
  printf '</head><body>%s</body></html>' "$html"
}
{
  printf '<?xml version="1.0" encoding="utf-8"?>\n'
  printf '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n<channel>\n'
  printf '<title>agx</title>\n<link>https://github.com/%s</link>\n<item>\n' "$GH_ORIGIN"
  printf '<title>Version %s</title>\n<pubDate>%s</pubDate>\n' "$VERSION" "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
  printf '<sparkle:version>%s</sparkle:version>\n<sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$VERSION" "$VERSION"
  printf '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>\n'
  printf '<description><![CDATA[%s]]></description>\n' "$(appcast_notes)"
  printf '<enclosure url="https://github.com/%s/releases/download/%s/%s" type="application/octet-stream" %s/>\n' \
    "$GH_ORIGIN" "$TAG" "$(basename "$DMG")" "$ED_ATTRS"
  printf '</item>\n</channel>\n</rss>\n'
} >"$APPCAST"
xmllint --noout "$APPCAST"
echo "==> appcast: $APPCAST"

if [ "$PUBLISH" != "1" ]; then
  echo "==> dry run complete (pass --publish to upload + bump the cask)"
  exit 0
fi

# ── publish: GitHub release + cask bump ───────────────────────────────────────
# a fork carries an `upstream` remote and gh may resolve its default repo there — pin the
# release to wherever origin points, never to upstream.
GH_REPO="$(git remote get-url origin | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
export GH_REPO
echo "==> publishing $TAG to $GH_REPO"
NOTES_FILE="$(mktemp)"
release_notes >"$NOTES_FILE"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release edit "$TAG" --title "Version $VERSION" --notes-file "$NOTES_FILE"
else
  gh release create "$TAG" --title "Version $VERSION" --notes-file "$NOTES_FILE"
fi
rm -f "$NOTES_FILE"
gh release upload "$TAG" "$DMG" "$APPCAST" --clobber
# The tag was minted on GitHub; scripts/build.sh reads the nearest LOCAL v-tag for the
# app version, so without this the next `make deploy` still stamps the previous version.
git -C "$ROOT" fetch -q origin "refs/tags/$TAG:refs/tags/$TAG"

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
TAP_DIR="$(mktemp -d)"
if ! gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth=1 >/dev/null 2>&1; then
  echo "==> tap $TAP_REPO not reachable — release is up, cask NOT bumped (create the tap and re-run)" >&2
  exit 0
fi
CASK="$TAP_DIR/Casks/agx.rb"
if [ ! -f "$CASK" ]; then
  mkdir -p "$TAP_DIR/Casks"
  cp "$ROOT/packaging/agx.rb" "$CASK" # first publish: seed from the in-repo source of truth
fi
sed -i '' -E "s/^( *version )\".*\"/\1\"$VERSION\"/" "$CASK"
sed -i '' -E "s/^( *sha256 )\".*\"/\1\"$SHA\"/" "$CASK"
git -C "$TAP_DIR" add Casks/agx.rb
if git -C "$TAP_DIR" diff --cached --quiet; then
  echo "==> cask already at $VERSION, nothing to push"
else
  git -C "$TAP_DIR" commit -m "agx $VERSION"
  git -C "$TAP_DIR" push
  echo "==> cask bumped to $VERSION"
fi
rm -rf "$TAP_DIR"
echo "==> done"
