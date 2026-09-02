import AppKit
import Foundation
import OSLog
import agtermCore

/// Owns the scheduled-session list for the app's lifetime: persists it, arms one timer for the next fire,
/// re-checks on display wake and at launch, and creates the session when a job is due. The app is the
/// long-lived process, so no launchd job is involved; a job the app slept through fires on the next
/// launch within `SchedulePolicy.missedGrace` and parks as missed after it.
@MainActor
@Observable
final class SessionScheduler {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "SessionScheduler")

    private(set) var items: [ScheduledSession] = []

    @ObservationIgnored private let store: ScheduleStore
    @ObservationIgnored private let library: WindowLibrary
    @ObservationIgnored private let actions: AppActions
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    init(directory: URL, library: WindowLibrary, actions: AppActions) {
        self.store = ScheduleStore(directory: directory)
        self.library = library
        self.actions = actions
    }

    /// Idempotent; called from the scene task once windows are restored so a due job has a store to land in.
    func start() {
        guard !started else { return }
        started = true
        items = store.load()
        wakeObserver = NotificationCenter.default.addObserver(forName: .agtermScreensDidWake, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        sweep()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NotificationCenter.default.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    func nodes(now: Date = Date()) -> [ControlScheduledNode] {
        items.sorted { $0.fireAt < $1.fireAt }.map { ControlScheduledNode.project($0, now: now) }
    }

    func item(withID id: UUID) -> ScheduledSession? { items.first { $0.id == id } }

    func add(_ item: ScheduledSession) -> Bool {
        do {
            try store.writeBrief(item)
            items.append(item)
            try store.save(items)
        } catch {
            Self.logger.error("add failed: \(error.localizedDescription, privacy: .public)")
            items.removeAll { $0.id == item.id }
            store.removeBrief(for: item.id)
            return false
        }
        emit(.scheduleAdded, item)
        sweep()
        return true
    }

    func cancel(_ id: UUID) -> Bool {
        guard let item = item(withID: id) else { return false }
        remove(item)
        emit(.scheduleCancelled, item)
        sweep()
        return true
    }

    /// Fires the job now whatever its time or missed state. Nil when it could not create the session; the
    /// job then stays listed so nothing is lost on a window that had not opened yet.
    func run(_ id: UUID) -> UUID? {
        guard let item = item(withID: id) else { return nil }
        let created = fire(item, activate: false)
        sweep()
        return created
    }

    /// Fire what is due, park what is stale, arm the timer for the earliest remaining job.
    private func sweep() {
        let now = Date()
        for item in items {
            switch SchedulePolicy.decide(item, now: now) {
            case .wait:
                continue
            case .fire:
                _ = fire(item, activate: item.foreground)
            case .missed where !item.isMissed:
                markMissed(item, now: now)
            case .missed:
                continue
            }
        }
        arm(now: now)
    }

    private func arm(now: Date) {
        timer?.invalidate()
        timer = nil
        guard let next = SchedulePolicy.nextFire(in: items, now: now) else { return }
        // `Timer(fireAt:)` survives sleep by firing late on wake, and the wake observer sweeps sooner.
        let timer = Timer(fire: max(next, now.addingTimeInterval(0.05)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire(_ item: ScheduledSession, activate: Bool) -> UUID? {
        guard let store = library.store(for: item.windowID) ?? library.activeStore else {
            Self.logger.error("fire \(item.id.uuidString, privacy: .public): no open window")
            return nil
        }
        guard let workspaceID = resolveWorkspace(item, in: store) else {
            Self.logger.error("fire \(item.id.uuidString, privacy: .public): no workspace")
            return nil
        }
        // rewritten here rather than trusted from add time: the file sits in a temp-like directory a cleanup
        // may have swept, and a fire with no brief would open an agent with nothing to do.
        do { try self.store.writeBrief(item) } catch {
            Self.logger.error("fire \(item.id.uuidString, privacy: .public): brief write failed")
            return nil
        }
        let seed = actions.newSessionSeed(in: store, workspaceID: workspaceID, requestedCwd: item.cwd,
                                          requestedCommand: item.launch,
                                          fallbackCwd: FileManager.default.homeDirectoryForCurrentUser.path)
        let command = ScheduledLaunch.commandLine(launch: seed.command, briefFile: self.store.briefFile(for: item.id))
        guard let session = store.addSession(toWorkspace: workspaceID, cwd: seed.cwd, command: command,
                                             name: item.name, select: item.foreground) else {
            Self.logger.error("fire \(item.id.uuidString, privacy: .public): could not create session")
            return nil
        }
        if item.foreground, store === library.activeStore { actions.focusActiveSession() }
        if activate { NSApp.activate(ignoringOtherApps: true) }
        remove(item, keepBrief: true)
        emit(.scheduleFired, item, session: session.id)
        NotificationManager.shared.send(toSession: session, title: "Scheduled session",
                                        body: item.name ?? String(item.brief.prefix(80)))
        Self.logger.notice("fired \(item.id.uuidString, privacy: .public) → session \(session.id.uuidString, privacy: .public)")
        return session.id
    }

    private func resolveWorkspace(_ item: ScheduledSession, in store: AppStore) -> UUID? {
        if let id = item.workspaceID, store.workspaces.contains(where: { $0.id == id }) { return id }
        if let name = item.workspaceName {
            return store.ensureWorkspace(named: name, revealNewWorkspace: item.foreground)?.id
        }
        return store.currentWorkspaceID ?? store.workspaces.first?.id
    }

    private func markMissed(_ item: ScheduledSession, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].missedAt = now
        save()
        emit(.scheduleMissed, items[index])
        NotificationManager.shared.notifyScheduleMissed(name: item.name ?? String(item.brief.prefix(60)))
        Self.logger.notice("missed \(item.id.uuidString, privacy: .public)")
    }

    private func remove(_ item: ScheduledSession, keepBrief: Bool = false) {
        items.removeAll { $0.id == item.id }
        if !keepBrief { store.removeBrief(for: item.id) }
        save()
    }

    private func save() {
        do { try store.save(items) } catch {
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func emit(_ kind: ControlEventKind, _ item: ScheduledSession, session: UUID? = nil) {
        library.recordControlEvent(ControlEventDraft(
            kind: kind, window: item.windowID?.uuidString, workspace: item.workspaceID?.uuidString,
            session: session?.uuidString ?? item.id.uuidString,
            payload: ControlEventPayload(name: item.name ?? String(item.brief.prefix(60)),
                                         at: ControlScheduledNode.isoString(item.fireAt))))
    }
}
