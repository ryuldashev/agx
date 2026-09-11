#!/usr/bin/env bash
# agx-session-restore — SessionStart hook: inside agx only, pin this pane's restore command to the
# agent's resume line for the session id on stdin, so a pane whose process is gone after a relaunch
# comes back into the same conversation instead of a bare shell.
#
#   --resume-line '<template>'   the agent's resume line with {id} for the session id
#                                (default: Claude Code's `claude --resume {id} --fork-session`)
#   --id-key <name>              the stdin JSON key carrying the id (default session_id; the common
#                                alternatives session_id / conversation_id are always tried too)
#
# The stdin JSON is read with python3 (jq is not assumed). Outside agx, or with nothing to read, it
# is a silent no-op; it prints nothing and always exits 0, so it can never block a turn.
#
# agtermctl resolution: $AGTERMCTL — an explicit override, or the bundled path the installer bakes
# in below — then `agtermctl` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

resume_line='claude --resume {id} --fork-session'
id_key=session_id
while [ $# -gt 0 ]; do
  case "$1" in
    --resume-line) resume_line=${2:-}; shift 2 ;;
    --id-key) id_key=${2:-session_id}; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$resume_line" ] || exit 0

sid="$(python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get(sys.argv[1]) or d.get("session_id") or d.get("conversation_id") or "")
except Exception:
    pass' "$id_key" 2>/dev/null)" || exit 0
[ -n "$sid" ] || exit 0
# the id lands inside a shell line; anything but an id-shaped token is refused rather than quoted
case "$sid" in *[!A-Za-z0-9_-]*) exit 0 ;; esac
line=${resume_line//\{id\}/$sid}

# forward the pane discriminators the app injected (see agterm-agent-status.sh for why both)
pane_args=()
[ -n "${AGTERM_PANE:-}" ] && pane_args+=(--pane "$AGTERM_PANE")
[ -n "${AGTERM_PANE_ID:-}" ] && pane_args+=(--pane-id "$AGTERM_PANE_ID")

"${AGTERMCTL:-agtermctl}" session restore "zsh -lc 'exec $line'" \
  --target "$AGTERM_SESSION_ID" "${pane_args[@]+"${pane_args[@]}"}" >/dev/null 2>&1 || true
exit 0
