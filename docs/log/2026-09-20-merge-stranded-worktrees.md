# 2026-09-20 — Merge the stranded worktrees, guard deploy, gc worktrees

Disk hit 1 GB free. Ten Claude worktrees held ~2.3 GB of build output each; seven of them held
finished features that were never merged — they had been deployed from the worktree, seen working,
and then overwritten by the next `make deploy` from master.

## Merged into master (three branches; four more were subsets of `integration`)
- `worktree-auto-update-2026-09-13` — Sparkle auto-update, `update.*`. ADR renumbered 0003 → **0004**.
- `worktree-private-sessions-2026-09-14` — private sessions. ADR renumbered 0003 → **0005**.
- `integration-2026-09-12` — agent profiles (per-agent `agent.json` manifests), the guide, the Keyboard
  Shortcuts sheet, the Welcome panel, the Brand rename. Master's `agx-artifacts.sh` hook went into
  `agents/claude/agent.json`; its four new actions (private session ×2, insert secret, artifacts) into
  `ShortcutsSheet`.
- Side fixes: `update.*` and `session.private` dispatch moved to `ControlDispatcher+Update/+Private`
  (file-length limit); `resolvesTheEntryIDAndItsPrefix` pinned to a fixed id (was flaky on all-digit
  prefixes).

## New
- `scripts/deploy-guard.sh` — `make deploy` refuses a branch master does not contain;
  `AGTERM_DEPLOY_PREVIEW=1` for a preview. Rule in CLAUDE.md.
- `scripts/gc.sh` / `make gc` — removes merged worktrees, drops build output of ones idle ≥3 days; runs
  after every `make deploy`.

## Next
- `make gc` now removes all seven worktrees (all merged). Push master.
- Sparkle needs the EdDSA key in the keychain (`agx`) before the next `make dist` — see ADR 0004.

## Later the same day

- v0.25.0 published (GitHub release + appcast + cask bump). `/Applications/agx.app` deployed at 0.25.0
  and relaunched; sessions survived the relaunch.
- Gotcha fixed in `scripts/release.sh`: `gh release create` mints the tag remotely while `build.sh`
  reads the nearest local v-tag, so the first `make deploy` after a release stamped the old version.
  The script now fetches the tag after publishing.
- Local `.claude/settings.json` (gitignored) allowlists `make deploy|dist|gc` + `./scripts/*.sh` and
  tells the auto-mode classifier this is the user's own app; note in CLAUDE.md. Allow rules match only
  a bare command — run scripts from the repo root, not via `cd … &&`.
