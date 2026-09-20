# Installers audit (Help > Install...) — static read-only review

Repo: agx worktree onboarding-2026-09-12. **NOTE: worktree was reset mid-audit to commit `26c9fd4`
("Show the hooks install result as agent rows with tiles and marks"), which lands
`agent-profiles-2026-09-11` (per-agent manifest catalog). This report reflects ONLY the current code at
that commit — an earlier draft written against the pre-refactor `AgentHooksInstaller` was fully discarded
and re-derived.**

Scope: AgentHooksInstaller (now generic over `AgentCatalog` manifests), SkillInstaller, CLIInstaller.
Rule followed: never executed agterm/agtermctl, never launched/quit the app, static reading only.

Key files (current):
- agterm/AgentHooksInstaller.swift (AppKit glue, generic over `status.kind`)
- agtermCore/Sources/agtermCore/AgentHooksInstall.swift (host-free JSON/TOML transforms)
- agtermCore/Sources/agtermCore/AgentCatalog.swift (manifest model `AgentProfile`/`StatusIntegration` + loader)
- agterm/Resources/agent-status/agents/<binary>/agent.json — 16 manifests (aider, amp, claude, codex,
  copilot, crush, cursor, droid, gemini, goose, hermes, kimi, mimo, opencode, pi, qwen)
- agterm/Views/AgentHooksResultView.swift — SwiftUI result WINDOW (replaced the old NSAlert)
- docs/decisions/0003-agent-profiles.md, docs/log/2026-09-11-agent-profiles.md — design rationale
- agterm/SkillInstaller.swift + agtermCore/Sources/agtermCore/SkillInstall.swift — **unchanged** by this
  refactor (confirmed via `git log` on those paths, no agent-profiles commit touches them)
- agterm/CLIInstaller.swift + agtermCore/Sources/agtermCore/CLIInstall.swift — **unchanged**
- Tests: agtermCore/Tests/agtermCoreTests/{AgentHooksInstallTests(40 @Test),AgentCatalogTests(20 @Test),
  SkillInstallTests,CLIInstallTests}.swift; agtermTests/AgentHooksInstallerTests.swift (5 XCTest, app-side,
  result-window text only)

## 1. AgentHooksInstaller (generic engine)

Files written by `install()` (agterm/AgentHooksInstaller.swift:104-109):
- `~/.config/agx/agent-status/` — bundled scripts copied wholesale, prior dir removed first
  (:124-133, `destinationFolder` :28-31, still brand-fixed via `Brand.configDirectoryName == "agx"`,
  independent of the running bundle's own location)
- Every `*.sh` file under that freshly-copied tree that references `${AGTERMCTL:-`/`${AGX:-` gets an
  absolute-path bake block inserted after its shebang (:143-160) — no longer a fixed list of 4 wrapper
  names; it's a directory `enumerator` scan, so it automatically covers whatever scripts a manifest ships
  (`agents/codex/status.sh`, `agx-session-restore.sh`, `agx-session-context.sh`, `agx-agent-failure.sh`, …).
  Because the folder was just wiped-and-recopied one step earlier, there is never a stale bake to strip —
  the old `stripBakedBlock` function is gone; baking is always onto pristine bundled content.
- `~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish` (:307-320, unchanged logic from before)
- Then **one step per agent manifest**, `AgentCatalog.known.filter(\.hasStatusIntegration)` (:108), each
  routed by `profile.status`'s `kind` (:111-122):
  - `.jsonHooks` → `mergeJSONHooks` (:218-238) — Claude (`~/.claude/settings.json`), Gemini
    (`~/.gemini/settings.json`), both `dialect: "claude"`. Cursor's `HookDialect.cursor` flat-row dialect
    exists in code and is tested (`cursorMergeWritesFlatRowsUnderVersionOne`,
    AgentHooksInstallTests.swift:112) but **no bundled manifest currently declares a `status` object with
    it** — `agents/cursor/agent.json` has no `status` key at all, so Cursor's `StatusIntegration` decodes
    to `.none` (launch + resume only; ADR 0003 explicitly: "Cursor and Mimo have no `status` until a live
    pane confirms their hook surface"). The cursor dialect is dead code in production today, live only in
    tests.
  - `.tomlHooks` → `mergeTOMLHooks` (:242-264) — only Codex today (`~/.codex/config.toml`).
  - `.plugin` → `installPlugin` (:269-304) — OpenCode (`~/.config/opencode/plugins/agterm-status.js`) and
    Pi (`~/.pi/agent/extensions/agterm-status.ts`).
  - `.none` → `.unchanged`, no-op (agents with no status integration are filtered out one line earlier
    anyway by `hasStatusIntegration`, so this arm is effectively unreachable from `install()`).

JSON shape merged (agtermCore AgentHooksInstall.swift:46-74), generic over `dialect`:
- `claude` dialect: `hooks.<Event>: [{matcher?, hooks:[{type:"command", command:"<cmd>"}]}]` — same shape
  as before, now driven by each manifest's `HookBinding` list instead of a hardcoded Swift array. Claude's
  manifest adds a 7th hook vs. the pre-refactor code: `StopFailure → agx-agent-failure.sh` (no args).
- `cursor` dialect (untriggered in practice, see above): `{version:1, hooks:{<event>:[{command:"<cmd>"}]}}`
  — flat, no matcher field, `version` seeded to `1` only if absent.

Idempotency guard: `entryUsesScript` (agtermCore AgentHooksInstall.swift:288-292) now checks BOTH
`entry["command"]` directly (covers the flat Cursor dialect) and the nested `entry["hooks"][].command`
(Claude/Gemini dialect) for the absolute script path substring. Re-running does not duplicate (tests:
`mergeWhenPresentIsNoOp`-equivalent coverage across the 40 `@Test`s in AgentHooksInstallTests.swift).

Can it overwrite/delete a user-authored hook? No — same as before, strictly additive per-event-array
append; nothing removes or mutates an entry it did not add. `destinationFolder` stays fixed
(`~/.config/agx/agent-status`), so the merge key is stable across rebuilds.

Backup: **now covers both JSON hooks AND TOML hooks**, via the new shared `writeConfig` helper
(agterm/AgentHooksInstaller.swift:201-208) — writes `.bak` beside the file (not the resolved symlink
target) with the target's original posix mode, whenever `existing` is non-empty, before every JSON-hooks
or TOML-hooks rewrite. This is a WIDENING vs. the pre-refactor code, which only backed up Claude and Codex
by name; now it's automatic for every `jsonHooks`/`tomlHooks` agent (i.e. Gemini too, once/if its manifest
status goes live). **Plugin installs (OpenCode, Pi) still get NO backup** — explicit in the comment at
agterm/AgentHooksInstaller.swift:267-268 ("no backup, unlike the hook files: the plugin carries no user
state") — same as before the refactor.

Malformed / edge cases — unchanged behavior, now generic:
- Non-JSON-object / unparseable content → `.skipped(reason: "isn't valid JSON", manual: false)`
  (agterm/AgentHooksInstaller.swift:232-234), file left untouched, no backup written (nothing changed).
- Unreadable file → `.skipped(reason: "exists but couldn't be read", manual: false)` (:225-227, :249-251).
- TOML file with its own `hooks` table → `.skipped(reason: "already defines its own hooks", manual: true)`
  (:256-257) — sends user to docs via `codexManualDocsURL`.
- Symlinked config files: `writeConfig`/`writePreservingSymlink` resolve and write through the symlink
  target, same as before (:172-183, :201-208).

Uninstall/revert: **still none.** No `uninstall()` anywhere in AgentHooksInstaller.swift or
AgentHooksInstall.swift. Only manual recovery path is the `.bak` file (jsonHooks/tomlHooks only) or hand
edits; plugin files have no backup at all to revert to.

Baked absolute paths / `make deploy`: same risk as before — `bundledTool`/`bundledFolder` resolve via
`Bundle.main` (agterm/AgentHooksInstaller.swift:19-26), and `make deploy` renames the outgoing app to
`agx.app.old` rather than deleting it (per root CLAUDE.md), so a stale bake keeps resolving until the NEXT
deploy overwrites that `.old`. Re-running the installer heals it (fresh copy + fresh bake every run, no
manual re-run needed to avoid duplicate blocks — but the RE-RUN itself is still manual, nothing re-bakes
automatically on relaunch).

Agents covered and gating: driven entirely by `agent.json`'s `configDirectory` field, checked via
`exists(configDirectory)` (agterm/AgentHooksInstaller.swift:212-214, 220, 244, called per-agent). Of the 16
bundled manifests, only 5 declare a `status` integration today: Claude (`jsonHooks`), Codex (`tomlHooks`),
Gemini (`jsonHooks`), OpenCode (`plugin`), Pi (`plugin`). Cursor, Mimo, aider, amp, copilot, crush, droid,
goose, hermes, kimi, qwen have no `status` block (`hasStatusIntegration == false`) — launch/resume only,
never touched by `AgentHooksInstaller.install()` at all (filtered out at :108 before the per-agent switch
even runs). Claude is now gated on `.claude` existing too (`mergeJSONHooks` checks `configDirectory` like
every other agent, agterm/AgentHooksInstaller.swift:220) — this is a change from the pre-refactor code,
where Claude's settings.json merge ran unconditionally and could seed `~/.claude` for a non-Claude user;
that special case is gone now, Claude is symmetric with every other agent.

## 2. Agent skill installer (SkillInstaller) — unchanged by this refactor

Confirmed via `git log` that no `agent-profiles` commit touches `agterm/SkillInstaller.swift` or
`agtermCore/Sources/agtermCore/SkillInstall.swift`. All findings from the pre-refactor read stand:
- Installs to `~/.claude/skills/agterm/` and/or `~/.codex/skills/agterm/`
  (agtermCore SkillInstall.swift:26-45), falling back to creating Claude's if neither agent dir exists.
- Plain recursive copy (`fm.copyItem`, agterm/SkillInstaller.swift:69), not a symlink.
- Refuses to overwrite an existing directory unless its `SKILL.md` carries the marker
  `<!-- agterm-skill -->` (agtermCore SkillInstall.swift:12, 51-55); lstat-based existence check specifically
  to avoid treating a dangling symlink as absent and deleting the user's own symlink
  (agterm/SkillInstaller.swift:55-58).
- No uninstall path anywhere.

## 3. CLI installer (CLIInstaller) — unchanged by this refactor

Confirmed via `git log`, no agent-profiles commit touches `agterm/CLIInstaller.swift` or
`agtermCore/Sources/agtermCore/CLIInstall.swift`. Findings stand:
- Symlinks (not copies) both `agtermctl` and `agx` into `/usr/local/bin`
  (agterm/CLIInstaller.swift:50-53,65; agtermCore CLIInstall.swift:14).
- Direct symlink if writable; else ONE combined `osascript … with administrator privileges` prompt
  (agterm/CLIInstaller.swift:74-85).
- **No ownership check at all** — `directSymlink` unconditionally `rm`s then `ln -sf`s whatever is already
  at the target path (agterm/CLIInstaller.swift:62-65), same for the privileged one-liner
  (agtermCore CLIInstall.swift:41-45, `ln -sf`). This remains the weakest of the three installers: it can
  silently clobber an unrelated tool that happens to be named `agx` or `agtermctl` on PATH, with no
  warning, no comparison, no backup.
- No uninstall path.

## 4. Status queries / control API exposure

**Still none.** Grepped the current tree for
`isInstalled|installedVersion|hooksInstalled|skillInstalled|cliInstalled` — zero matches. The new
`AgentCatalog.detectInstalled()` (agtermCore AgentCatalog.swift:329-335) answers a DIFFERENT question — "is
this agent CLI present on PATH/known install dirs" (used for Settings ▸ Agents' "Found on This Mac" list,
per docs/log/2026-09-11-agent-profiles.md) — not "did the hooks/skill/CLI installer already run for it".
There is still no persisted or queryable "installed / not installed" state for any of the three Help ▸
Install actions, and nothing is exposed on the control API / `agtermctl` / `tree` for install status.
Menu wiring unchanged in shape: three `Button { X.run() }` actions.

## 5. First-launch behavior outside the state dir

Re-verified against current `agtermApp.swift`/`WelcomeAlert.swift`/`FirstRunWelcome.swift` — logic
unchanged by the agent-profiles refactor:
- `WelcomeAlert` shows once per install (`isDue`: `!welcomeShown && !hasPriorState`), with two checkboxes
  **both defaulted ON** ("Install the agent skill", "Install the agent status hooks",
  agterm/WelcomeAlert.swift:69). Clicking the default "Install" button fires `SkillInstaller.run()` and the
  now-generic `AgentHooksInstaller.run()` automatically (agterm/WelcomeAlert.swift:36-37) — a first-time
  user who just clicks through gets `~/.claude/skills/agterm`, Claude's `settings.json` hooks (now gated on
  `.claude` existing, see §1), shell rc edits, and conditionally Gemini/Codex/OpenCode/Pi files written
  without visiting the Help menu. `settingsModel.setWelcomeShown(true)` is set BEFORE the installers run,
  so a failed/cancelled install cannot re-trigger the welcome.
- `PermissionsAlert`/`PermissionPrimer` chains after the welcome, same as before — `PermissionProbe.probe`
  triggers real TCC prompts via `contentsOfDirectory` on protected folders off the main thread
  (agterm/Permissions/PermissionProbe.swift:30-45).
- CLI installer is still NOT part of the auto-run checkbox set; Help menu is the only path to it.

## 6. Existing tests

- `agtermCore/Tests/agtermCoreTests/AgentHooksInstallTests.swift` — **40** `@Test`s (up from 37
  pre-refactor): JSON-hooks merge (claude dialect) idempotency/malformed-refusal/unrelated-preservation,
  the untriggered Cursor flat-dialect merge (`cursorMergeWritesFlatRowsUnderVersionOne`,
  `cursorMergeIntoAnEmptyFileAddsVersion`, :112,134), generic TOML merge (append/idempotent/
  upgrade-preserving-trust-state/foreign-marker-untouched/legacy-notify-stripped/unparseable/hooksExist),
  shell RC append, backup-path derivation, posix-mode-preserving write. Still **pure logic only**, no
  filesystem/AppKit.
- `agtermCore/Tests/agtermCoreTests/AgentCatalogTests.swift` — **20** `@Test`s (new file for this
  refactor): manifest decoding, `installTargets`-equivalent resolution, `detect`/`detectInstalled` PATH
  probing, `resumeCommand` id-shape validation, malformed-manifest skip-not-fatal behavior. Per ADR 0003:
  "asserts every bundled [manifest] decodes and that every script it names exists" — i.e. this suite is
  what guards the 16 `agent.json` files against drift/typos, not the installer's filesystem side effects.
- `agtermTests/AgentHooksInstallerTests.swift` — **5** XCTest methods (down from 6; renamed/restructured
  for the new result-window model): `testNoDetailEmbedsTheHooksBlockOrAHomePath`,
  `testOnlyTheManualMergeOutcomesOfferTheDocsButton`, `testSkippedDetailNamesTheFileNotItsPath`,
  `testMergedDetailCarriesTheAgentsActivateStep`, `testDocsURLPointsAtTheManualMergeAnchor`. Still tests
  **only the result-window text/row content**, not any actual filesystem write (settings.json merge,
  script baking, shell RC, TOML/plugin writes) — those remain entirely unverified by any test that runs the
  app-side `AgentHooksInstaller` against real files; only the pure `agtermCore` layer is exercised.
- SkillInstaller/CLIInstaller test coverage unchanged from before: `SkillInstallTests.swift` (11 @Test),
  `CLIInstallTests.swift` (7 @Test), both pure-logic only; **no app-side test exists for either** — their
  AppKit glue (symlink creation, admin-prompt fallback, actual copy) is entirely unexercised by any test.

## 7. Per-`status.kind` audit: marker-guarded / idempotent / reversible / uninstall

| kind | agents (live today) | marker mechanism | idempotent | reversible | uninstall |
|---|---|---|---|---|---|
| `jsonHooks` | Claude, Gemini (Cursor dialect coded, unused) | **No literal marker.** Idempotency is structural: `entryUsesScript` parses the JSON and checks whether an entry's `command` already contains the absolute script path (agtermCore AgentHooksInstall.swift:288-292) — there is no sentinel string embedded anywhere in the written JSON that says "agterm put this here". A user (or another tool) could add a bare-looking entry with the same script path and it would read as already-installed. | Yes — re-run detects existing per-event entries by script path and skips them (verified by tests). | Only via the `.bak` file `writeConfig` writes before any change (agterm/AgentHooksInstaller.swift:204-205); no in-place un-merge that strips just agterm's entries out of a live-edited file. | **None.** No code removes the hook entries it added. |
| `tomlHooks` | Codex | **Yes, textual.** `rcMarkerBegin`/`rcMarkerEnd` (`# >>> agterm agent-status >>>` / `# <<<`) wrap the whole generated block (agtermCore AgentHooksInstall.swift:24-25, 174-180). The idempotency/refresh probe on re-run additionally checks the block's body contains `/agent-status/` (:193) — a generic, package-name-based check (no longer Codex-specific wrapper-name matching) so it recognizes ANY agent's script inside a marked block. Refuses to touch a file that already defines its own `[hooks...]` (`hooksExist`) or fails to parse (`unparseable`) — surfaced to the user as a manual-merge case with a docs link. | Yes — re-run refreshes only the content between the markers, preserving Codex's own trailing `[hooks.state...]` trust tables byte-for-byte (:182-214), and is a no-op if the refreshed block matches (`unchanged`). | Because the block IS delimited by textual markers, a user *could* manually delete the `# >>> … # <<<` region by hand — but nothing in the app does this automatically; there is no `restore.toml`/undo command. The `.bak` backup (`writeConfig`, agterm/AgentHooksInstaller.swift:204-205) is the only automated fallback, and it captures the file as of the LAST install, not necessarily pristine pre-agterm state if the installer has run and been edited by the user since. | **None.** No `unmergeTOMLHooks`/removal function exists. |
| `plugin` | OpenCode, Pi | **Yes, embedded in file content.** A single-line ownership comment (`// agterm-opencode-status-plugin`, `// agterm-pi-status-extension`, both from the manifest's `marker` field) must be present in the ENTIRE existing file for a reinstall to be allowed to overwrite it (`mayOverwritePlugin`, agtermCore AgentHooksInstall.swift:30-34). Unlike the other two kinds this isn't a delimited sub-block — the whole plugin/extension file is agterm's or it isn't; there's no merging into a larger user file. | Yes — re-run compares byte-for-byte (`existing != contents` → `.unchanged` else copy, agterm/AgentHooksInstaller.swift:293). | **No backup at all** — explicitly by design (agterm/AgentHooksInstaller.swift:267-268: "the plugin carries no user state"), so there is nothing automated to revert to; the only recovery is re-copying from the bundle (which the installer already does on every run) or manually deleting the file. | **None.** No code deletes the plugin/extension file it wrote. |

Cross-kind takeaway: none of the three `status.kind`s has an uninstall path — this is a repo-wide gap, not
a per-kind one. Backup coverage is asymmetric: `jsonHooks`/`tomlHooks` get a `.bak` (via the shared
`writeConfig`), `plugin` gets none. Only `tomlHooks` uses an actual textual marker sentinel for its
idempotency probe; `jsonHooks` idempotency is structural (script-path lookup, no marker string written into
the JSON itself) and `plugin` idempotency is whole-file marker/content comparison.

## Summary: honest / hole per installer

**AgentHooksInstaller** — mostly honest, well-guarded, backup coverage IMPROVED by this refactor
(jsonHooks now backed up too, not just the two agents hardcoded before):
- Honest: append-only for hooks, never deletes/overwrites a user's own entries; TOML/plugin ownership gates
  refuse to touch foreign files; generic bake-scan means new agent scripts get their paths baked
  automatically; Claude is no longer a special-cased ungated agent.
- Holes: no uninstall for any of the three kinds; plugin writes still get no backup; baked absolute CLI
  path can go stale across `make deploy` cycles (manual re-run required to heal); auto-fires two of the
  three installers on first launch via default-checked Welcome checkboxes; `jsonHooks` idempotency relies
  on a script-path lookup rather than an explicit ownership marker, unlike its TOML/plugin siblings; Cursor
  dialect code path is untested-in-production (no live manifest exercises it outside unit tests).

**SkillInstaller** — unchanged, same conclusions as before: honest ownership-marker gate, no uninstall,
plain copy (not symlink) so it silently drifts from newer bundled versions until manually re-run.

**CLIInstaller** — unchanged, still the weakest: **no ownership check at all**, unconditionally
force-overwrites whatever sits at `/usr/local/bin/agtermctl`/`/usr/local/bin/agx`; no uninstall.

## Open questions / gaps
- Did not execute anything; all conclusions are from static reading, consistent with the required
  restriction, re-derived after the mid-task worktree reset.
- Whether Gemini's `Notification` matcher and any future live Cursor `status` block behave as documented is
  explicitly flagged as unverified in the project's own ADR 0003 ("on a documented contract, not on an
  observed run") — outside this static-audit's ability to confirm either way.
- Did not re-verify PermissionsAlert beyond confirming its wiring is untouched by the agent-profiles
  refactor; a fuller Permissions audit remains out of scope.
