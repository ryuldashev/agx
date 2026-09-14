import AppKit
import Foundation
import OSLog
import agtermCore

/// Answers a permission prompt the user left alone: a session enters `blocked` (Claude Code's
/// `permission_prompt` notification hook, Codex's footer watcher), a countdown HUD goes up over it, and after
/// the Settings grace — counted from the user's last move when they are in that session — the app injects the
/// affirmative key through the same path `session type` uses. The decision is `AutoAnswerPolicy`'s, made at
/// FIRE time against the pane's visible text; this owns the timers, the presence check, the HUD, the keystroke
/// and the user-facing notice. Armed from `setSessionStatus`; `session.autoanswer` flips the per-session
/// override.
@MainActor
final class AutoAnswerCoordinator {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "AutoAnswer")
    /// How often the countdown HUD is redrawn.
    static let hudTick: TimeInterval = 5

    private let library: WindowLibrary
    private let settingsModel: SettingsModel
    /// Sizes the countdown HUD from the live pane; wired in the scene `.task` after both exist.
    weak var controlServer: ControlServer?
    /// One token per armed session; a fire whose token is stale (re-armed, cancelled) is a no-op.
    private var pending: [UUID: UUID] = [:]
    private var hudTickScheduled = false

    init(library: WindowLibrary, settingsModel: SettingsModel) {
        self.library = library
        self.settingsModel = settingsModel
    }

    private var settings: AppSettings { settingsModel.settings }

    /// The status just changed. A transition INTO `blocked` starts the grace; anything else cancels a running
    /// one (a keystroke cleared it, the hook reported `active`, the session closed). A `blocked` re-asserted
    /// over `blocked` is the same episode and does not restart the clock.
    func statusChanged(session: Session, wasBlocked: Bool, store: AppStore) {
        guard session.agentIndicator.status == .blocked else {
            cancel(session.id)
            return
        }
        guard !wasBlocked, pending[session.id] == nil else { return }
        guard session.autoAnswer.effectiveEnabled(settings: settings.effectiveAutoAnswerEnabled) else { return }
        arm(session, store: store, after: TimeInterval(settings.effectiveAutoAnswerDelaySeconds))
    }

    /// `session.autoanswer on|off`: an `off` drops the running grace; an `on` while already blocked starts one.
    func setEnabled(_ enabled: Bool, session: Session, store: AppStore) {
        session.autoAnswer.enabledOverride = enabled
        if enabled {
            if session.agentIndicator.status == .blocked {
                statusChanged(session: session, wasBlocked: false, store: store)
            }
        } else {
            cancel(session.id)
        }
    }

    // MARK: - grace

    private func arm(_ session: Session, store: AppStore, after delay: TimeInterval) {
        let id = session.id
        let token = UUID()
        pending[id] = token
        session.autoAnswer.dueAt = Date().addingTimeInterval(delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.fire(id, token: token) }
        showHud(session, store: store, remaining: delay)
        scheduleHudTick()
    }

    private func cancel(_ id: UUID) {
        pending.removeValue(forKey: id)
        if let store = library.store(forSession: id), let session = store.session(withID: id) {
            session.autoAnswer.dueAt = nil
            closeHud(session, store: store)
        }
    }

    /// The grace ran out. Everything is re-checked here rather than trusted from arm time: the user may have
    /// answered (status cleared), Settings may have changed, they may be sitting in the session reading it,
    /// and the prompt's text is only known now.
    private func fire(_ id: UUID, token: UUID) {
        guard pending[id] == token else { return }
        pending.removeValue(forKey: id)
        guard let store = library.store(forSession: id), let session = store.session(withID: id) else { return }
        guard session.agentIndicator.status == .blocked,
              session.autoAnswer.effectiveEnabled(settings: settings.effectiveAutoAnswerEnabled) else {
            cancel(id)
            return
        }
        let remaining = AutoAnswerPresence.remainingGrace(delay: TimeInterval(settings.effectiveAutoAnswerDelaySeconds),
                                                          userInSession: isUserIn(session, store: store),
                                                          idle: store.idleSeconds)
        if remaining > 0 {
            arm(session, store: store, after: remaining)
            return
        }
        session.autoAnswer.dueAt = nil
        let binary = AgentFailoverCoordinator.agentBinary(of: session)
        let agent = AutoAnswerAgent.of(binary: binary)
        let surface = blockedSurface(session)
        let screen = surface.flatMap { $0.isRealized ? $0.readScreenText(all: false, lines: nil) : nil }
        var decision = AutoAnswerPolicy.decide(screen: screen, agent: agent)
        closeHud(session, store: store)
        if case .answer(let keys) = decision, surface?.inject(text: keys) != true {
            decision = .hold(reason: "could not type into the pane")
        }
        session.autoAnswer.record(decision)
        announce(decision, session: session, store: store, agent: binary)
    }

    /// The user is IN the session when it is the selected one of the frontmost window of the active app —
    /// what is on their screen right now. Anywhere else (another session, another app) the prompt is a
    /// background one and the plain grace applies.
    private func isUserIn(_ session: Session, store: AppStore) -> Bool {
        NSApp.isActive && library.windowID(for: store) == library.frontmostWindowID
            && store.activeSession?.id == session.id
    }

    /// The pane whose prompt blocked: the split when the status came from there, else the main pane. A
    /// scratch-owned block is not an agent prompt.
    private func blockedSurface(_ session: Session) -> GhosttySurfaceView? {
        switch session.agentIndicator.statusPane ?? .left {
        case .left: return session.surface as? GhosttySurfaceView
        case .right: return session.splitSurface as? GhosttySurfaceView
        case .scratch: return nil
        }
    }

    // MARK: - countdown HUD

    /// Opens or refreshes the countdown over the session. A slot held by a caller's program is left alone
    /// (`openHud` refuses it); a HUD someone else put up is replaced only by this one's own.
    private func showHud(_ session: Session, store: AppStore, remaining: TimeInterval) {
        guard let controlServer else { return }
        let agent = AutoAnswerAgent.of(binary: AgentFailoverCoordinator.agentBinary(of: session))
        let spec = AutoAnswerHud.spec(remaining: remaining, agent: agent)
        let size = HudLayout.panelSize(for: spec, pane: controlServer.paneMetrics(for: session))
        if session.hudActive {
            guard AutoAnswerHud.owns(session.hudSpec) else { return }
            store.updateHud(session.id, spec: spec, size: size)
        } else if !session.programOverlayActive {
            store.openHud(session.id, spec: spec, size: size)
        }
    }

    private func closeHud(_ session: Session, store: AppStore) {
        guard session.hudActive, AutoAnswerHud.owns(session.hudSpec) else { return }
        store.closeHud(session.id)
    }

    /// One redraw pass per `hudTick` while anything is armed; the chain ends itself when nothing is.
    private func scheduleHudTick() {
        guard !hudTickScheduled else { return }
        hudTickScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudTick) { [weak self] in
            guard let self else { return }
            self.hudTickScheduled = false
            let now = Date()
            for id in self.pending.keys {
                guard let store = self.library.store(forSession: id), let session = store.session(withID: id),
                      let due = session.autoAnswer.dueAt else { continue }
                self.showHud(session, store: store, remaining: due.timeIntervalSince(now))
            }
            if !self.pending.isEmpty { self.scheduleHudTick() }
        }
    }

    // MARK: - notice

    private func announce(_ decision: AutoAnswerDecision, session: Session, store: AppStore, agent: String?) {
        let name = session.displayName
        let payload = ControlEventPayload(name: name, action: decision.name, reason: decision.reason, agent: agent)
        library.recordControlEvent(ControlEventDraft(
            kind: .autoAnswer, window: library.windowID(for: store)?.uuidString,
            workspace: store.workspace(forSession: session.id)?.id.uuidString,
            session: session.id.uuidString, payload: payload))
        let title: String
        let body: String
        switch decision {
        case .answer:
            title = "Auto-answered"
            body = "“\(name)”: nobody answered the \(agent ?? "agent") prompt for \(settings.effectiveAutoAnswerDelaySeconds)s — said yes."
        case .hold(let reason):
            title = "Agent needs you"
            body = "“\(name)” is waiting on a prompt the app will not answer (\(reason))."
        }
        NotificationManager.shared.send(toSession: session, title: title, body: body)
        Self.logger.notice("\(session.id.uuidString, privacy: .public): \(decision.name, privacy: .public) \(decision.reason ?? "", privacy: .public)")
    }
}
