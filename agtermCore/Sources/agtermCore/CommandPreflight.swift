import Foundation

/// Pure checks that decide whether a surface `command` is safe to EXEC as-is.
///
/// A surface spawned with a command execs that argv directly instead of running a login shell, so an
/// unresolvable binary exits 127 and the pane closes the instant it opens — a session that vanishes with
/// nothing on screen to explain it. The platform side resolves the binary against the effective `PATH`
/// (`CommandPreflight.Resolution`); this half is the host-free parsing it needs, kept testable.
public enum CommandPreflight {
    /// Characters that mean the string is a SHELL line, not a bare argv: resolving its first word would be
    /// wrong (`VAR=1 cmd`, `a && b`, `f | g`, `$(x)`), so preflight declines to judge those and lets them run.
    private static let shellMetacharacters = Set("|&;<>()$`\\\"'*?[]{}~#!\n")

    /// The executable word to look up, or nil when the command must not be judged: empty, shell syntax, or
    /// already an explicit path (`/usr/bin/x`, `./x`, `~/x`), which the spawn resolves on its own.
    ///
    /// nil means "spawn it unchanged" in every case — preflight only ever speaks up about a bare name it is
    /// certain it can check, so a false alarm cannot cost the user a working command.
    public static func executableToken(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(where: shellMetacharacters.contains) else { return nil }
        guard let first = trimmed.split(separator: " ", maxSplits: 1).first else { return nil }
        let token = String(first)
        guard !token.contains("/") else { return nil }
        // `VAR=1 cmd` — an env prefix, so the first word is not the binary either. `=` is not in the
        // metacharacter set above because it is legal INSIDE a binary name; only a leading word carrying it
        // means shell syntax.
        guard !token.contains("=") else { return nil }
        return token
    }

    /// The message shown in the pane that opens in place of a command that could not be resolved. States the
    /// command, the cause, and the fix, and names the app so it reads as agterm speaking, not the shell.
    public static func unresolvedMessage(command: String) -> String {
        let token = executableToken(command) ?? command
        return "agterm: \"\(token)\" not found in PATH — opening a shell instead. "
            + "Fix the command (Settings ▸ Agents, or the workspace default) or install it, then reopen."
    }
}
