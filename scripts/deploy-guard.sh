#!/usr/bin/env bash
# `make deploy` from a branch that master does not contain installs work that the next deploy from
# master silently removes — that is how four finished features vanished from /Applications in
# September 2026 while their worktrees sat unmerged. A preview deploy is still allowed, but it has to
# be asked for by name.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

branch=$(git rev-parse --abbrev-ref HEAD)
main_ref=$(git rev-parse --verify -q master || git rev-parse --verify -q origin/master || true)
[ -n "$main_ref" ] || exit 0

if git merge-base --is-ancestor HEAD "$main_ref"; then
  exit 0
fi
if [ "${AGTERM_DEPLOY_PREVIEW:-}" = "1" ]; then
  echo "deploy: PREVIEW of unmerged branch '$branch' — the next deploy from master REMOVES it. Merge before you call this feature done." >&2
  exit 0
fi
cat >&2 <<MSG
deploy: refusing to install unmerged branch '$branch'.
  What you see in /Applications after this would disappear at the next deploy from master.
  Merge into master first, then deploy from the main checkout; for a throwaway preview:
    AGTERM_DEPLOY_PREVIEW=1 make deploy
MSG
exit 1
