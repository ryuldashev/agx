# 2026-09-16 — Insert Secret (iTerm2 password manager for agx)

Ask: "в iTerm был механизм хранения секретов (рут паролей) с быстрой вставкой — нужно в agx."

Branch: `worktree-secrets-2026-09-16` (worktree from origin/master ddda9df).

## What shipped
- Keychain-backed secrets: `KeychainSecretStore` (app target, `Security`), one generic-password item per
  label under `Brand.keychainService = uz.marshub.agx.secrets`. No cache, no file.
- Built-in `insert_secret` (⌥⌘F, iTerm2's chord) → `PaletteMode.secrets`: labels as rows, Enter types
  the value into the surface pinned when the palette opened (`AppActions.secretTargetSurface`), so a
  scratch/split that had focus gets it, not the main pane. Edit ▸ Insert Secret… menu item.
- Control: `secret.list|add|remove|insert`; dispatcher validation in `ControlDispatcher+Secret.swift`
  (label ≤64, value ≤4096, no control chars). `secret.insert` reuses `injectText` (= `session.type`).
  Value crosses the socket only inbound; never returned; journal never records it.
- CLI: `agtermctl secret add <label>` reads the value from stdin ONLY (termios hidden prompt on a tty,
  piped text otherwise). No `--value` flag on purpose.
- Tests: dispatcher (host-free), CLI, protocol round-trip, keymap.list/BuiltinAction/PaletteCatalog pins,
  `InsertSecretUITests` (menu → palette → typed into pane; socket insert; remove; missing-label errors).
- Docs: site/commands.html `secret` section, docs.html action list, skill reference + SKILL.md,
  `control-api.md` catalog, FORK.md, `agx context` hint line for agents facing a password prompt.

## Findings
- XCUITest `typeKey` with ⌥ on a letter fires no menu equivalent in this app (⌥⌘N is equally inert), so
  the UI test drives the Edit menu; the chord is verified by hand. Not a feature bug.
- `agtermctl session type` takes the text positionally, not `--text` (my own slip during manual test).
- Keychain items created by a Debug/test build carry that build's ACL; the Release app is asked once
  before reading them. Test labels are unique and removed in tearDown.

## Not done (deliberately)
- No Settings pane. Adding is the palette's last row, Add Secret… (`SecretAddPrompt`, an NSAlert with a
  label and a secure field, same `SecretPolicy` wording as the CLI; Save reopens the palette so the new
  secret can be inserted at once). Ruslan asked for it the moment he saw the CLI-only version. Removal
  stays CLI-only.
- No "send Return after" option; `session type $'\n'` follows an insert when a script needs it.
