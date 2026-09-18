#!/usr/bin/env bash
# agx-artifacts — Claude Code PostToolUse hook: inside agx only, record the files the agent just SHOWED
# the user in the artifact index (`agtermctl artifact add`), so they can be found again from the
# Artifacts window without reopening the conversation. Three showings count: a Bash `open <file|url>`
# (any flags; `-a App` and `-R` kept out of the paths), `agx reader <file.md>`, and `SendUserFile`.
# Writes and edits are deliberately not artifacts — an intermediate file was never put in front of anyone.
#
# The hook's stdin JSON carries the tool name, its input, the cwd and the transcript id; python3 parses it
# (jq is not assumed). A `cd <dir> &&` prefix inside the command moves the base for a relative path.
# Outside agx, on any other tool, or with nothing to read, it is a silent no-op; it prints nothing and
# always exits 0 so a broken index never stalls the agent.
#
# agtermctl resolution: $AGTERMCTL — an explicit override, or the bundled path the installer bakes in
# below — then `agtermctl` on PATH.
set -u

[ "${AGTERM_ENABLED:-}" = "1" ] || exit 0   # not inside agx: nothing to do
[ -n "${AGTERM_SESSION_ID:-}" ] || exit 0

input="$(cat)" || exit 0
case "$input" in
    *'"SendUserFile"'*) ;;
    *'"Bash"'*) case "$input" in *open*|*reader*) ;; *) exit 0 ;; esac ;;
    *) exit 0 ;;
esac

# one artifact per line: source<TAB>base dir<TAB>path or URL<TAB>title
rows="$(printf '%s' "$input" | python3 -c '
import json, os, shlex, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
tool = d.get("tool_name") or ""
inp = d.get("tool_input") or {}
cwd = d.get("cwd") or os.getcwd()
out = []

def emit(source, base, ref, title=""):
    ref = str(ref).strip()
    if not ref or ref in (".", "..") or ref.startswith("-"):
        return
    if not ref.startswith(("http://", "https://")):
        full = ref if ref.startswith(("/", "~")) else os.path.join(base, ref)
        full = os.path.expanduser(full)
        if os.path.isdir(full):
            return
    out.append("\t".join([source, base, ref, " ".join(str(title).split())[:200]]))

if tool == "SendUserFile":
    for f in inp.get("files") or []:
        emit("sendfile", cwd, f, inp.get("caption") or "")
elif tool == "Bash":
    text = inp.get("command") or ""
    if "open" not in text and "reader" not in text:
        sys.exit(0)
    try:
        lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        words = list(lexer)
    except ValueError:
        sys.exit(0)
    base = cwd
    segments, current = [], []
    for w in words:
        if w in ("&&", "||", ";", ";;", "|", "&"):
            segments.append(current); current = []
        else:
            current.append(w)
    segments.append(current)
    for seg in segments:
        if not seg:
            continue
        # an `env VAR=x` / `VAR=x cmd` prefix hides the verb
        while seg and ("=" in seg[0] and not seg[0].startswith(("/", ".", "~")) or seg[0] == "env"):
            seg = seg[1:]
        if not seg:
            continue
        verb, rest = seg[0], seg[1:]
        if verb == "cd" and rest:
            target = os.path.expanduser(rest[0])
            base = target if target.startswith("/") else os.path.join(base, target)
        elif verb == "open":
            skip = False
            for a in rest:
                if a in ("<", ">", ">>", "2>", "&>"):
                    break
                if skip:
                    skip = False; continue
                if a in ("-a", "-b", "-s", "-e", "-t", "-h", "--env", "--args", "--stdin", "--stdout", "--stderr"):
                    skip = a in ("-a", "-b", "-s", "--env", "--stdin", "--stdout", "--stderr")
                    if a == "--args": break
                    continue
                if a.startswith("-"):
                    continue
                emit("open", base, a)
        elif verb == "agx" and rest[:1] == ["reader"]:
            args = rest[1:]
            title = ""
            i = 0
            while i < len(args):
                a = args[i]
                if a == "--title" and i + 1 < len(args):
                    title = args[i + 1]; i += 2; continue
                if a.startswith("-") or a == "close":
                    i += 1; continue
                emit("reader", base, a, title)
                i += 1
print("\n".join(out))
' 2>/dev/null)" || exit 0
[ -n "$rows" ] || exit 0

transcript="$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id") or "")
except Exception: pass' 2>/dev/null)"

while IFS=$'\t' read -r source base ref title; do
    [ -n "$ref" ] || continue
    args=(artifact add "$ref" --source "$source" --cwd "$base" --session "$AGTERM_SESSION_ID")
    [ -n "$title" ] && args+=(--title "$title")
    [ -n "$transcript" ] && args+=(--agent-session "$transcript")
    [ -n "${AGTERM_SOCKET:-}" ] && args+=(--socket "$AGTERM_SOCKET")
    "${AGTERMCTL:-agtermctl}" "${args[@]}" >/dev/null 2>&1 || true
done <<< "$rows"
exit 0
