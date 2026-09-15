# Supervisor model — answer the agent's QUESTIONS, not only its permission prompts

Status: proposed 2026-09-15 (Ruslan: "если/когда добавим доп-модель поверх agx, которая могла бы
принимать решения более умно-автономно, оно будет отвечать на вопросы. Сейчас рановато и не так уж
нужно"). Parked on purpose; nothing built.

## What
Auto-answer (ADR 0003) says Yes to an unattended permission prompt and holds everything else. The
other thing a background agent stalls on is a question to the user — Claude Code's `AskUserQuestion`
("which color / which approach / deploy now?"), Codex's input request. Today those are
`held reason=question for the user` plus a notification, and the pane waits for a human. A model
sitting above the panes could answer most of them from the brief and the transcript, and escalate the
rest.

## Why not now
- The permission case is a form check (question + Yes option, no destructive text) — deterministic,
  instant, offline, wrong at worst by one manual answer. A question needs a judgement about the
  TASK; a wrong pick silently steers the work. Different risk class, different product.
- Hold + notification already removes the "nobody noticed for an hour" pain; the residual cost is one
  keystroke per question.

## Where it plugs in (the seam already exists)
- `AutoAnswerPolicy.decide` (`agtermCore/AutoAnswer.swift`) returns `.hold(reason: "question for the
  user")`. That branch is the call site: hand the dialog region + a transcript tail
  (`ClaudeTranscript.digest` from failover already reads the JSONL) + the session's brief to the
  supervisor; it returns an option number, free text for "Type something.", or "ask the human".
- Everything around it reuses as is: grace + presence rule (never over a user who is reading),
  countdown HUD (message would say "Supervisor answers in N s"), `inject(text:)` for the keystroke
  (`<n>` + Return for a numbered option), the `auto_answer` event and notification (action
  `answered`, new field `by: supervisor`, the option text in `reason`), the per-session `session
  autoanswer off` override, the tree read-back.
- Keep the destructive catalog in front of it: a supervisor's answer that would approve a
  `DestructiveCommand` still holds.

## Open decisions when picked up
- Which model and where it runs (local `codex exec --json`, `claude -p`, Token Factory) and its
  budget per question; a 30-second timeout falls back to hold.
- Confidence gate: the supervisor must be allowed to say "ask the human"; a forced pick is worse
  than a hold. Log every pick with its rationale in the event payload so a wrong one is auditable.
- Settings: separate toggle under Settings ▸ Agents ▸ Auto-answer, default OFF.
