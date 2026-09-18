# 2026-09-18 — Failover: safeguards flag walks the ladder

**What changed.** A Claude Code turn ending in `API Error: <Model>'s safeguards flagged this message`
(`invalid_request`) used to classify as `blocked` → notify only, and the pane sat there. It is now
`safetyFlagged`: one resend of the continue prompt 5 s later (the classifier is probabilistic and a
resend often passes), then `/model <next>` down the ladder skipping every RELEASE that flagged — not the
family, since Opus 4.8 classifies on its own. The default ladder is `opus[1m]`, `claude-opus-4-8[1m]`,
`sonnet[1m]`; the usage-pool path still dedups by family, so 4.8 is skipped when the Opus pool is dry.
The continue prompt after a flag says the refusal was a false positive, not a usage error, so the agent
does not read it as a hint to drop the task.

- `agtermCore/AgentFailover.swift`: `AgentFailureKind.safetyFlagged`, `AgentFailure.flaggedModel`,
  `ModelFamily.version/sameModel/latest`, `FailoverState.flagRetries/triedModels/flaggedModels`,
  `FailoverPolicy.defaultFlaggedContinuePrompt/flagRetryDelay/maxFlagRetries`; read-back gains
  `flagRetries`, `tried`, `flagged`.
- `AgentFailoverCoordinator`: the prompt is chosen per failure; a customised continue prompt covers all.
- Verified against Claude Code 2.1.276: `claude-opus-4-8[1m]` is an accepted `/model` argument and the
  StopFailure error type for the flag is `invalid_request`.

**Gotcha.** `ModelFamily.latest` (`opus` → `5`, `fable` → `5.1`, …) is what lets "Opus 5 (1M context)"
match the bare alias `opus[1m]`; when Claude Code repoints an alias, bump the table or a flag on the new
release will retry the alias.

**Next.** Live test on a real flag: watch `tree` → `failover.flagged` and the pane's `/model` line.
