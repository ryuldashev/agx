# agents/<binary>/

One folder per agent CLI. `agent.json` is everything agx knows about it; an adapter the agent needs
lives beside it (`codex/status.sh`, `opencode/plugin.js`, `pi/extension.ts`). Both the app
(`AgentCatalog.swift`) and the `agx` CLI read these files; no code names an agent.

```jsonc
{
  "order": 0,                        // position on Settings ▸ Agents; omitted → last
  "name": "Claude Code",
  "binary": "claude",                // the command, also the identity
  "icon": { "glyph": "✳", "tint": "#D97757" },   // tile in Settings and the installer; default: first letter, grey
  "command": "claude",               // launch line seeded on Connect (default: binary)
  "seedFlag": "-i",                  // `<binary> -i "<brief>"`; omitted → positional
  "resume": "claude --resume {id}",  // restore line after a relaunch; omitted → no resume
  "configDirectory": ".claude",      // relative to ~; must exist before hooks are installed
  "context": "sessionStartHook",     // or "briefPrefix" (default): how `agx context` reaches it
  "trust": { "kind": "claudeProjects", "file": "~/.claude.json" },   // agx spawn's folder-trust probe
  "status": {                        // omitted → no status glyph
    "kind": "jsonHooks", "file": ".claude/settings.json", "dialect": "claude",   // or "cursor"
    "hooks": [{ "event": "Stop", "matcher": null, "script": "agterm-agent-status.sh", "args": ["completed", "--auto-reset"] }],
    "activate": "…"                  // one line shown after install, if the agent needs a step
  }
}
```

Other `status.kind`s: `tomlHooks` (`file`, `script`, `events: [{event, action}]` — Codex's
`[[hooks.*]]` block) and `plugin` (`source`, `destination`, `requires`, `marker` — copied once
`requires` exists, overwritten only when the existing file carries `marker`). Scripts and sources are
relative to the package root. Measured facts behind each manifest: `docs/reference/agents/<binary>.md`.
