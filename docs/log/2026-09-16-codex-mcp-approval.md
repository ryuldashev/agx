# 2026-09-16 — Codex MCP tool-approval form, Codex SessionStart JSON

A Codex session sat on "Allow the codebase-memory-mcp MCP server to run tool …?" until the user
answered by hand. Neither layer knew the form: the footer watcher matched only
`enter to submit answer|all`, so the session never went blocked; the policy would have vetoed
`enter to submit` as a question to the user and pressed `y`, which that list ignores.

- `d648ff4` on master: watcher matches `enter to submit`; `AutoAnswerPolicy` recognizes the form
  before the veto and answers with Return. Deployed; takes effect on the next app relaunch.
- Installed hooks in `~/.config/agx/agent-status/` patched by hand (`.bak-2026-09-16` beside each):
  the watcher pattern, and `hookEventName: "SessionStart"` in the `--format codex` envelope —
  Codex 0.154 requires it, otherwise "hook returned invalid session start JSON output" and no
  `agx context` for Codex sessions. The installed package is from the unmerged
  `agent-profiles-2026-09-11` branch (layout `agents/<agent>/status.sh`); that branch still
  carries the JSON bug and the old watcher pattern. Fix both there before merging.

Next: the HUD detail still says "press y" for Codex; it would say Return for the MCP form.
Cosmetic, left.
