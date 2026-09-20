import Foundation

// MARK: - Private sessions (ADR 0005)

extension AppStore {
    /// Marks a session private (or public again) and persists — the save is what drops the row from disk,
    /// since `snapshot()` skips private sessions. Idempotent like `setFlag`; no-op for an unknown id. The
    /// sink lets the app side write or clear the session's pending-cleanup entry.
    public func setPrivate(_ on: Bool, forSession id: UUID) {
        guard let session = session(withID: id), session.isPrivate != on else { return }
        session.isPrivate = on
        save()
        privateSessionSink?(session)
    }

    /// Records the agent session id a `session.restore` pin names, so a private close knows what to erase.
    /// Called on every pin, private or not: the flag can be turned on later, after the id arrived.
    func noteAgentSession(fromRestoreCommand command: String?, forSession session: Session) {
        guard let target = PrivateSessionCleanup.target(fromRestoreCommand: command),
              !session.agentSessionTargets.contains(target) else { return }
        session.agentSessionTargets.append(target)
        if session.isPrivate { privateSessionSink?(session) }
    }
}

extension PrivateSessionCleanup {
    /// The agent and session id behind a restore line: `claude --resume <id> …` or `codex resume <id>`
    /// (the lines the bundled SessionStart hooks pin). Nil for anything else — a plain shell, an `ssh`.
    public static func target(fromRestoreCommand command: String?) -> Target? {
        guard let command else { return nil }
        if let id = ClaudeTranscript.sessionID(fromRestoreCommand: command), command.contains("claude") {
            return Target(agent: .claude, sessionID: id)
        }
        if let range = command.range(of: "codex resume ") {
            let id = command[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return id.isEmpty ? nil : Target(agent: .codex, sessionID: String(id))
        }
        return nil
    }
}
