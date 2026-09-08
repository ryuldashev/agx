#!/usr/bin/env bash
# agx-session-restore — Claude Code SessionStart hook: inside agx only, pin this pane's restore
# command to `claude --resume <session_id> --fork-session`, so a pane whose process is gone after a
# relaunch comes back into the same conversation instead of a bare shell.
#
# The session id comes from the hook's stdin JSON, read with python3 (jq is not assumed). Outside
# agx, or with nothing to read, it is a silent no-op; it prints nothing and always exits 0, so it
# can never block a turn.
#
# agtermctl resolution: $AGTERMCTL — an explicit override, or the bundled path the installer bakes
# in below — then `agtermctl` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

sid="$(python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("session_id") or "")
except Exception:
    pass' 2>/dev/null)" || exit 0
[ -n "$sid" ] || exit 0
# the id lands inside a shell line; anything but an id-shaped token is refused rather than quoted
case "$sid" in *[!A-Za-z0-9_-]*) exit 0 ;; esac

# forward the pane discriminators the app injected (see agterm-agent-status.sh for why both)
pane_args=()
[ -n "${AGTERM_PANE:-}" ] && pane_args+=(--pane "$AGTERM_PANE")
[ -n "${AGTERM_PANE_ID:-}" ] && pane_args+=(--pane-id "$AGTERM_PANE_ID")

"${AGTERMCTL:-agtermctl}" session restore "zsh -lc 'exec claude --resume $sid --fork-session'" \
  --target "$AGTERM_SESSION_ID" "${pane_args[@]+"${pane_args[@]}"}" >/dev/null 2>&1 || true
exit 0
