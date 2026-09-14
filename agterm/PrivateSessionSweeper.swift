import Foundation
import OSLog
import agtermCore

/// App half of private sessions (ADR 0003): keeps `<stateDir>/private-cleanup.json` in step with the live
/// tree and runs `PrivateSessionCleanup.sweep` — a beat after a close, so the agent's process has exited
/// and flushed, and at launch for entries a crash left behind. Results go to the log and one banner.
@MainActor
final class PrivateSessionSweeper {
    static let shared = PrivateSessionSweeper()

    private static let logger = Logger(subsystem: Brand.bundleID, category: "PrivateSession")
    /// A closing pty SIGHUPs the program; Claude Code writes its last transcript lines on the way out.
    static let closeGrace: TimeInterval = 2.0
    static let launchGrace: TimeInterval = 3.0

    private var store = PrivateCleanupStore()

    func configure(stateDirectory: URL) {
        store = PrivateCleanupStore(directory: stateDirectory)
    }

    /// The session was marked private/public or learned an agent session id: record what a sweep would need
    /// NOW, so a crash before the close still leaves the next launch the ids.
    func sessionChanged(_ session: Session) {
        if session.isPrivate, !session.agentSessionTargets.isEmpty {
            store.upsert(PrivateSessionCleanup.Pending(id: session.id, targets: session.agentSessionTargets))
        } else {
            store.remove(session.id)
        }
    }

    /// The session is closed for good. The entry is (re)written first: the grace is where a crash would lose it.
    func sessionDiscarded(_ session: Session) {
        guard session.isPrivate else { return }
        let pending = store.upsert(PrivateSessionCleanup.Pending(id: session.id, targets: session.agentSessionTargets))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self] in
            self?.run(pending)
        }
    }

    /// Entries a previous run never swept. The launch's orphan reap has killed their durable servers, if any;
    /// the grace lets those programs exit before their files go.
    func sweepPendingAfterLaunch() {
        let items = store.load()
        guard !items.isEmpty else { return }
        Self.logger.notice("\(items.count, privacy: .public) private session(s) pending cleanup from a previous run")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchGrace) { [weak self] in
            for item in items { self?.run(item) }
        }
    }

    private func run(_ pending: PrivateSessionCleanup.Pending) {
        let roots = PrivateSessionCleanup.Roots.standard()
        Task.detached(priority: .utility) {
            let report = PrivateSessionCleanup.sweep(pending, roots: roots)
            await MainActor.run { PrivateSessionSweeper.shared.finish(pending, report: report) }
        }
    }

    private func finish(_ pending: PrivateSessionCleanup.Pending, report: PrivateSessionCleanup.Report) {
        // an entry with a failure stays for the next launch; one with none, or with no ids to act on, is done.
        if report.failed.isEmpty { store.remove(pending.id) }
        let summary = pending.targets.isEmpty
            ? "no agent session id was reported by its hooks; \(report.summary)"
            : report.summary
        Self.logger.notice("private session \(pending.id.uuidString, privacy: .public) swept: \(summary, privacy: .public)")
        for path in report.failed {
            Self.logger.error("private session \(pending.id.uuidString, privacy: .public): could not remove \(path, privacy: .private)")
        }
        NotificationManager.shared.notifyPrivateSweep(sessionID: pending.id, summary: summary)
    }
}
