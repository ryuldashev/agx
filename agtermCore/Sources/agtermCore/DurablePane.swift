import Foundation

/// Host-free half of durable panes (ADR 0001): a `--command` session's pane runs its program as a client
/// of a detached abduco server named by the session id, so the program outlives the app. The app target
/// owns the binary path, the file checks, the pid read and the kill; everything decidable off the C
/// boundary lives here.
public enum DurablePane {
    /// `sun_path` caps at 104 bytes; leave room for the NUL and the `.pid` sidecar.
    public static let maxSocketLength = 99

    public static func socketPath(stateDirectory: String, sessionID: UUID) -> String {
        stateDirectory + "/abduco/" + sessionID.uuidString
    }

    public static func pidFilePath(socket: String) -> String { socket + ".pid" }

    public static func fits(socket: String) -> Bool { socket.utf8.count <= maxSocketLength }

    /// The line the server runs: the exec `command`, else the restore override typed line minus its
    /// newline. A plan with neither is a plain login shell, never wrapped — unless a server already exists
    /// for the session (`restoreRunningCommand` off after a restart): attaching a live process is not the
    /// re-run that toggle guards, so the pane attaches, with a login shell as the `-f` fallback.
    public static func programLine(_ plan: CommandRestore.RestorePlan, serverExists: Bool = false) -> String? {
        if let command = plan.command, !command.isEmpty { return command }
        if let input = plan.initialInput {
            let line = input.hasSuffix("\n") ? String(input.dropLast()) : input
            if !line.isEmpty { return line }
        }
        return serverExists ? "/bin/zsh -l" : nil
    }

    /// Whether a spawn wraps: the setting, a `session.new --durable` request, or a server that already
    /// exists for the session — a restart must reattach even after the setting was turned off.
    public static func shouldWrap(settingOn: Bool, requested: Bool, serverExists: Bool, line: String?) -> Bool {
        line != nil && (settingOn || requested || serverExists)
    }

    /// The libghostty `command` (run through `sh -c`): `abduco -A -f <socket> /bin/zsh -lc '<wrapper>'`.
    /// `-A` attaches when the server is alive, else creates; `-f` replaces a server whose program already
    /// exited while detached instead of closing the pane with its exit status. The wrapper records `$$` —
    /// the program's pid once `exec` replaces the shell, unchanged by any further exec in `line` — so the
    /// app can read the program's argv and find the server (its parent) without guessing.
    public static func command(abduco: String, socket: String, line: String) -> String {
        let wrapper = "printf %d $$ >\(quote(pidFilePath(socket: socket))); exec \(line)"
        return "\(quote(abduco)) -A -f \(quote(socket)) /bin/zsh -lc \(quote(wrapper))"
    }

    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
