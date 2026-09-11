#!/usr/bin/env bash
# agx-agent-failure — Claude Code StopFailure hook: inside agx only, report the turn-ending API error to
# the app (`agtermctl session failure`), which switches the pane's model when the model's usage pool ran
# dry, re-prompts after a transient error, or hands the task to another connected agent.
#
# The error type, the message and the transcript path come from the hook's stdin JSON, read with python3
# (jq is not assumed). Outside agx, or with nothing to read, it is a silent no-op; it prints nothing and
# always exits 0 (Claude Code ignores a StopFailure hook's output anyway).
#
# agtermctl resolution: $AGTERMCTL — an explicit override, or the bundled path the installer bakes in
# below — then `agtermctl` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

# one line each: error type, transcript path, message (newlines folded so the three stay three lines)
fields="$(python3 -c 'import json, sys
try:
    d = json.load(sys.stdin)
    err = str(d.get("error") or "unknown").strip().split()[0]
    msg = " ".join(str(d.get("last_assistant_message") or d.get("error_details") or "").split())
    print(err); print(d.get("transcript_path") or ""); print(msg[:2000])
except Exception:
    pass' 2>/dev/null)" || exit 0
[ -n "$fields" ] || exit 0
error="$(printf '%s\n' "$fields" | sed -n 1p)"
transcript="$(printf '%s\n' "$fields" | sed -n 2p)"
message="$(printf '%s\n' "$fields" | sed -n 3p)"
[ -n "$error" ] || exit 0

args=(session failure "$error" --target "$AGTERM_SESSION_ID")
[ -n "$message" ] && args+=(--message "$message")
[ -n "$transcript" ] && args+=(--transcript "$transcript")
[ -n "${AGTERM_SOCKET:-}" ] && args+=(--socket "$AGTERM_SOCKET")

"${AGTERMCTL:-agtermctl}" "${args[@]}" >/dev/null 2>&1 || true
exit 0
