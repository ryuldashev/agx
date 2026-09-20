#!/usr/bin/env bash
# Reclaim disk from Claude worktrees under .claude/worktrees.
# Each worktree carries ~2.3 GB of regenerable output (build/ + agtermCore/.build); ten of them once
# filled the disk. Merged worktrees are removed; idle ones lose only their build output.
set -euo pipefail
cd "$(dirname "$0")/.."

IDLE_DAYS="${AGTERM_GC_DAYS:-3}"
now=$(date +%s)
here=$(pwd -P)
freed_kb=0
kept=()

git fetch -q origin master 2>/dev/null || true

for w in .claude/worktrees/*/; do
  [ -d "$w" ] || continue
  w=${w%/}
  wp=$(cd "$w" && pwd -P)
  [ "$wp" = "$here" ] && continue
  branch=$(git -C "$w" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  size_kb=$(du -sk "$w" | cut -f1)

  if git merge-base --is-ancestor "$branch" origin/master 2>/dev/null \
     && [ -z "$(git -C "$w" status --porcelain 2>/dev/null)" ]; then
    git worktree remove --force "$w"
    git branch -D "$branch" >/dev/null 2>&1 || true
    freed_kb=$((freed_kb + size_kb))
    echo "removed  $w  ($branch merged)"
    continue
  fi

  last=$(git -C "$w" log -1 --format=%ct 2>/dev/null || echo 0)
  git_mtime=$(stat -f %m "$w/.git" 2>/dev/null || echo 0)
  [ "$git_mtime" -gt "$last" ] && last=$git_mtime
  idle_days=$(( (now - last) / 86400 ))
  if [ "$idle_days" -ge "$IDLE_DAYS" ] && { [ -d "$w/build" ] || [ -d "$w/agtermCore/.build" ]; }; then
    before=$size_kb
    rm -rf "$w/build" "$w/agtermCore/.build"
    after=$(du -sk "$w" | cut -f1)
    freed_kb=$((freed_kb + before - after))
    echo "cleaned  $w  (idle ${idle_days}d, build output dropped)"
  fi
  kept+=("$w  $branch  idle ${idle_days}d  ahead $(git rev-list --count origin/master.."$branch" 2>/dev/null || echo ?)")
done

git worktree prune
echo "freed $((freed_kb / 1024)) MB"
if [ ${#kept[@]} -gt 0 ]; then
  echo "unmerged worktrees still on disk:"
  printf '  %s\n' "${kept[@]}"
fi
