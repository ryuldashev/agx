import AppKit
import Foundation
import OSLog
import agtermCore

/// Acts on an agent's failure in a pane: types `/model <next>` and a continue prompt when the model's usage
/// pool ran dry, re-prompts after a transient error, or opens a peer session with another connected agent
/// seeded with a brief built from the failed session's transcript. The decision is `FailoverPolicy`'s;
/// this owns the typing, the spawn and the user-facing notice. Reached from `session.failure` (the Claude
/// Code `StopFailure` hook) and from a main-pane exit while the agent was mid-turn.
@MainActor
final class AgentFailoverCoordinator {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "AgentFailover")
    /// The pause between `/model …` and the continue prompt: Claude Code confirms the switch first, and a
    /// prompt typed while it is still handling the slash command lands in the same line.
    static let modelSwitchSettle: TimeInterval = 2.5
    /// The gap between a typed line and its Return, so the TUI's paste detection has closed the burst.
    static let returnSettle: TimeInterval = 0.4
    /// The gap before the safety Return that submits a prompt whose first Return was swallowed.
    static let returnRepeat: TimeInterval = 1.5
    /// How much of a transcript's tail the handoff digest reads; the last prompts and answer sit there.
    static let transcriptTailBytes = 4_000_000

    private let briefDirectory: URL
    private let library: WindowLibrary
    private let settingsModel: SettingsModel

    init(directory: URL, library: WindowLibrary, settingsModel: SettingsModel) {
        self.briefDirectory = directory.appendingPathComponent("failover", isDirectory: true)
        self.library = library
        self.settingsModel = settingsModel
    }

    private var settings: AppSettings { settingsModel.settings }

    /// Decide and act. Returns what was done; `session.failover` carries the same in read-back form.
    @discardableResult
    func report(_ failure: AgentFailure, session: Session, store: AppStore, transcript: String? = nil,
                forceHandoff: Bool = false) -> FailoverAction {
        if let transcript { session.agentTranscriptPath = transcript }
        guard settings.effectiveFailoverEnabled else {
            let action = FailoverAction.notify(reason: "agent failover is off in Settings")
            session.failover = FailoverPolicy.advance(session.failover, failure: failure, action: action)
            return action
        }
        let sourceBinary = Self.agentBinary(of: session) ?? "claude"
        let agent = settings.effectiveFailoverHandoffEnabled ? settings.failoverHandoffAgent(for: sourceBinary) : nil
        var action: FailoverAction
        if forceHandoff {
            action = agent != nil
                ? .handoff(reason: "handoff requested")
                : .notify(reason: "handoff requested but no other agent is connected")
        } else {
            action = FailoverPolicy.decide(failure, state: session.failover,
                                           ladder: settings.effectiveFailoverModels, handoffAvailable: agent != nil)
        }
        var newSession: Session?
        switch action {
        case .switchModel(let model):
            if !switchModel(model, in: session) {
                action = .notify(reason: "could not type into the pane to switch the model")
            }
        case .retry(let delay):
            if !retry(after: delay, in: session) {
                action = .notify(reason: "could not type into the pane to retry")
            }
        case .handoff(let reason):
            if let agent, let created = handoff(session, store: store, agent: agent, reason: reason,
                                                sourceBinary: sourceBinary) {
                newSession = created
            } else {
                action = .notify(reason: "\(reason), and the handoff session could not be opened")
            }
        case .notify:
            break
        }
        session.failover = FailoverPolicy.advance(session.failover, failure: failure, action: action)
        if let newSession { session.failover.handedOffTo = newSession.id }
        announce(action, failure: failure, session: session, store: store, newSession: newSession)
        return action
    }

    /// A main-pane program exited while the agent's status was still `active`: it died mid-turn rather than
    /// being quit at a prompt (an interrupt or any keystroke would have cleared the status first). Hands the
    /// task on before the session closes. Never during quit, when every pane is being torn down.
    func paneExiting(session: Session, store: AppStore) {
        guard settings.effectiveFailoverEnabled, settings.effectiveFailoverHandoffEnabled,
              !library.isTerminating, session.agentIndicator.status == .active,
              session.failover.handedOffTo == nil, Self.agentBinary(of: session) != nil else { return }
        let failure = AgentFailure(kind: .processExited, errorType: "process_exited",
                                   message: "the agent process exited while its status was active")
        report(failure, session: session, store: store)
    }

    // MARK: - actions

    private func switchModel(_ model: String, in session: Session) -> Bool {
        guard type("/model \(model)", into: session) else { return false }
        let id = session.id
        pressReturn(in: id, after: Self.returnSettle)
        after(Self.modelSwitchSettle) { [weak self] in self?.submitPrompt(in: id) }
        return true
    }

    private func retry(after delay: TimeInterval, in session: Session) -> Bool {
        guard (session.surface as? GhosttySurfaceView)?.isRealized == true else { return false }
        let id = session.id
        after(delay) { [weak self] in self?.submitPrompt(in: id) }
        return true
    }

    /// Type the continue prompt and submit it. The text goes in one burst and the Return comes separately:
    /// Claude Code treats a burst as a paste and swallows a Return that arrives inside it, so a prompt typed
    /// `text + "\n"` sits in the input box unsent. A second Return follows in case the first landed while
    /// the TUI was still digesting the paste; on an empty input it is a no-op.
    private func submitPrompt(in id: UUID) {
        guard let session = liveSession(id), type(settings.effectiveFailoverContinuePrompt, into: session) else { return }
        pressReturn(in: id, after: Self.returnSettle)
        pressReturn(in: id, after: Self.returnSettle + Self.returnRepeat)
    }

    private func pressReturn(in id: UUID, after delay: TimeInterval) {
        after(delay) { [weak self] in
            guard let self, let session = self.liveSession(id) else { return }
            _ = self.type("\n", into: session)
        }
    }

    private func after(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
    }

    private func liveSession(_ id: UUID) -> Session? {
        library.store(forSession: id)?.session(withID: id)
    }

    private func type(_ text: String, into session: Session) -> Bool {
        guard let surface = session.surface as? GhosttySurfaceView else { return false }
        return surface.inject(text: text)
    }

    private func handoff(_ session: Session, store: AppStore, agent: AgentDefinition, reason: String,
                         sourceBinary: String) -> Session? {
        guard let workspace = store.workspace(forSession: session.id) else { return nil }
        let cwd = session.effectiveCwd
        let transcript = session.agentTranscriptPath ?? Self.derivedTranscriptPath(session, cwd: cwd)
        let digest = transcript.flatMap(Self.tail).map { ClaudeTranscript.digest(jsonl: $0) } ?? ClaudeTranscript.Digest()
        let brief = HandoffBrief(reason: reason, sourceName: session.displayName, sourceAgent: sourceBinary,
                                 cwd: cwd, transcriptPath: transcript, digest: digest).compose()
        let briefFile = briefDirectory.appendingPathComponent("\(UUID().uuidString).brief")
        do {
            try FileManager.default.createDirectory(at: briefDirectory, withIntermediateDirectories: true)
            try Data(brief.utf8).write(to: briefFile, options: .atomic)
        } catch {
            Self.logger.error("handoff: brief write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let command = ScheduledLaunch.commandLine(launch: agent.launchCommand, briefFile: briefFile.path)
        // a private session's handoff is private too: the brief carries its transcript digest.
        guard let created = store.addSession(toWorkspace: workspace.id, cwd: cwd, command: command,
                                             name: "\(session.displayName) → \(agent.name)",
                                             isPrivate: session.isPrivate, select: false) else {
            try? FileManager.default.removeItem(at: briefFile)
            return nil
        }
        Self.logger.notice("handoff \(session.id.uuidString, privacy: .public) → \(agent.name, privacy: .public) session \(created.id.uuidString, privacy: .public)")
        return created
    }

    private func announce(_ action: FailoverAction, failure: AgentFailure, session: Session, store: AppStore,
                          newSession: Session?) {
        let name = session.displayName
        var payload = ControlEventPayload(name: name, action: action.name)
        var title = "Agent failover"
        var body: String
        switch action {
        case .switchModel(let model):
            payload.model = model
            body = "“\(name)”: \(failure.model ?? "the model") ran out of usage — switched to \(model) and continued."
        case .retry(let delay):
            body = "“\(name)”: \(failure.errorType) — retrying in \(Int(delay))s."
        case .handoff(let reason):
            payload.reason = reason
            payload.source = session.id.uuidString
            body = "“\(name)” stopped (\(reason)); \(newSession?.displayName ?? "another agent") took over."
        case .notify(let reason):
            payload.reason = reason
            title = "Agent needs you"
            body = "“\(name)”: \(failure.message.isEmpty ? failure.errorType : failure.message) — \(reason)."
        }
        library.recordControlEvent(ControlEventDraft(
            kind: .failover, window: library.windowID(for: store)?.uuidString,
            workspace: store.workspace(forSession: session.id)?.id.uuidString,
            session: (newSession ?? session).id.uuidString, payload: payload))
        NotificationManager.shared.send(toSession: newSession ?? session, title: title, body: body)
        Self.logger.notice("\(session.id.uuidString, privacy: .public): \(failure.kind.rawValue, privacy: .public) → \(action.name, privacy: .public)")
    }

    // MARK: - helpers

    /// The agent CLI the main pane runs, from the pinned restore line (the SessionStart hook's
    /// `claude --resume …`) or the launch command (`agx spawn`'s `exec claude "$b"`).
    static func agentBinary(of session: Session) -> String? {
        AgentBinary.of(commandLine: session.restoreCommand) ?? AgentBinary.of(commandLine: session.initialCommand)
    }

    /// The transcript a `claude --resume <id>` restore line implies, when the file exists.
    static func derivedTranscriptPath(_ session: Session, cwd: String) -> String? {
        guard let id = ClaudeTranscript.sessionID(fromRestoreCommand: session.restoreCommand) else { return nil }
        let path = ClaudeTranscript.transcriptPath(home: FileManager.default.homeDirectoryForCurrentUser.path,
                                                   cwd: cwd, sessionID: id)
        return FileManager.default.isReadableFile(atPath: path) ? path : nil
    }

    /// The last `transcriptTailBytes` of the file, from the first whole line; nil when unreadable.
    static func tail(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(transcriptTailBytes) ? size - UInt64(transcriptTailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") { text = String(text[text.index(after: newline)...]) }
        return text
    }
}
