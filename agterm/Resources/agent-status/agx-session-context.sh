#!/usr/bin/env bash
# agx-session-context — Claude Code SessionStart hook: inside agx only, hand the new session a
# description of the UI it lives in (the output of `agx context`) as additionalContext.
#
# Outside agx (AGTERM_ENABLED unset) it prints nothing. It never blocks a turn: every failure is
# swallowed and the exit code is always 0. The JSON envelope is built by python3, which agx itself
# needs anyway, so jq is not required.
#
# agx resolution: $AGX — an explicit override, or the bundled Contents/Resources/agx path the
# installer bakes in below — then `agx` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do

agx="${AGX:-}"
if [ -z "$agx" ]; then
  agx="$(command -v agx 2>/dev/null)" || exit 0
fi
ctx="$("$agx" context 2>/dev/null)" || exit 0
[ -n "$ctx" ] || exit 0

python3 - "$ctx" 2>/dev/null <<'PY' || true
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": sys.argv[1],
}}))
PY
exit 0
