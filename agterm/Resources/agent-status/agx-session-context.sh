#!/usr/bin/env bash
# agx-session-context — SessionStart hook: inside agx only, hand the new session a description of
# the UI it lives in (the output of `agx context`) as additional context.
#
#   --format claude   {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": …}}
#                     (default; Claude Code, Gemini CLI and Codex read this envelope)
#   --format codex    the same envelope without hookEventName (Codex documents only additionalContext)
#   --format cursor   {"additional_context": …}  (Cursor's sessionStart)
#
# Outside agx (AGTERM_ENABLED unset) it prints nothing. It never blocks a turn: every failure is
# swallowed and the exit code is always 0. The JSON envelope is built by python3, which agx itself
# needs anyway, so jq is not required.
#
# agx resolution: $AGX — an explicit override, or the bundled Contents/Resources/agx path the
# installer bakes in below — then `agx` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do

format=claude
while [ $# -gt 0 ]; do
  case "$1" in
    --format) format=${2:-claude}; shift 2 ;;
    *) shift ;;
  esac
done

agx="${AGX:-}"
if [ -z "$agx" ]; then
  agx="$(command -v agx 2>/dev/null)" || exit 0
fi
ctx="$("$agx" context 2>/dev/null)" || exit 0
[ -n "$ctx" ] || exit 0

python3 - "$ctx" "$format" 2>/dev/null <<'PY' || true
import json, sys
ctx, fmt = sys.argv[1], sys.argv[2]
if fmt == "cursor":
    print(json.dumps({"additional_context": ctx}))
elif fmt == "codex":
    print(json.dumps({"hookSpecificOutput": {"additionalContext": ctx}}))
else:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }}))
PY
exit 0
