import Foundation

public enum RecentClosedKind: String, Codable, Sendable {
    case session
    case workspace
}

public struct RecentClosedItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: RecentClosedKind
    public let title: String
    public let subtitle: String?
    public let closedAt: Date
    public let session: RecentClosedSession?
    public let workspace: RecentClosedWorkspace?

    public init(id: UUID = UUID(), kind: RecentClosedKind, title: String, subtitle: String?,
                closedAt: Date = Date(), session: RecentClosedSession? = nil,
                workspace: RecentClosedWorkspace? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.closedAt = closedAt
        self.session = session
        self.workspace = workspace
    }
}

public struct RecentClosedSession: Codable, Equatable, Sendable {
    public let workspaceID: UUID
    public let workspaceName: String
    public let workspaceIndex: Int
    public let sessionIndex: Int
    public let snapshot: SessionSnapshot

    public init(workspaceID: UUID, workspaceName: String, workspaceIndex: Int, sessionIndex: Int,
                snapshot: SessionSnapshot) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.workspaceIndex = workspaceIndex
        self.sessionIndex = sessionIndex
        self.snapshot = snapshot
    }
}

public struct RecentClosedWorkspace: Codable, Equatable, Sendable {
    public let snapshot: WorkspaceSnapshot
    public let selectedSessionID: UUID?
    /// Whether the workspace was a MEMBER of the sidebar focus set when it closed, so Reopen Closed Item can
    /// mark it again instead of appending it invisibly behind a still-applied filter. Membership ONLY — the
    /// filter FLAG is deliberately not recorded, being current window state rather than a property of the
    /// closed workspace (see `AppStore.markFocusMember`). OPTIONAL because this struct persists in
    /// `recent-closed.json`: a required key would fail the whole decode of an older file, and
    /// `RecentClosedStore.load()` turns a decode failure into an EMPTY list — the user's entire recent list.
    /// Absent (nil) reads as "not a member", the behavior of every pre-existing entry.
    public let focusMember: Bool?

    public init(snapshot: WorkspaceSnapshot, selectedSessionID: UUID?, focusMember: Bool? = nil) {
        self.snapshot = snapshot
        self.selectedSessionID = selectedSessionID
        self.focusMember = focusMember
    }
}

/// One recently-closed entry as `restore.list` reports it, and as `restore.open` addresses it.
public struct ControlRecentClosedNode: Codable, Sendable, Equatable {
    /// 1-based position in the newest-first list, and what `restore.open <index>` takes.
    public let index: Int
    /// The entry's own id — stable across listings, unlike `index`, so a script should carry this.
    public let id: String
    /// `session` or `workspace`.
    public let kind: String
    public let title: String
    public let workspace: String?
    public let cwd: String?
    /// ISO 8601 with the local offset.
    public let closedAt: String
    /// The closed session's id (kind `session`), so a caller can address an entry by what `tree` last showed.
    public let sessionID: String?
    /// Member count for kind `workspace`.
    public let sessions: Int?
    /// The pinned launch line a reopen will run — the agent resume line a session-start hook wrote, or nil
    /// when the pane comes back as a plain shell. Answers "does reopening this get my agent back".
    public let restoreCommand: String?

    public init(index: Int, id: String, kind: String, title: String, workspace: String?, cwd: String?,
                closedAt: String, sessionID: String?, sessions: Int?, restoreCommand: String?) {
        self.index = index
        self.id = id
        self.kind = kind
        self.title = title
        self.workspace = workspace
        self.cwd = cwd
        self.closedAt = closedAt
        self.sessionID = sessionID
        self.sessions = sessions
        self.restoreCommand = restoreCommand
    }

    public static func project(_ item: RecentClosedItem, index: Int,
                               timeZone: TimeZone = .current) -> ControlRecentClosedNode {
        // an empty pin is `session.restore --none`: a deliberate plain shell, which reads the same as none here.
        let pin = item.session?.snapshot.restoreCommand.flatMap { $0.isEmpty ? nil : $0 }
        return ControlRecentClosedNode(
            index: index, id: item.id.uuidString, kind: item.kind.rawValue, title: item.title,
            workspace: item.kind == .session ? item.session?.workspaceName : item.title,
            cwd: item.session?.snapshot.cwd,
            closedAt: ControlISO8601.string(item.closedAt, timeZone: timeZone),
            sessionID: item.session?.snapshot.id.uuidString,
            sessions: item.workspace?.snapshot.sessions.count,
            restoreCommand: pin)
    }
}

/// Resolving `restore.open`'s target against the recent list.
public enum RecentClosedResolve {
    /// An all-digit target is the printed INDEX and NOTHING else — out of range it is `.notFound`, never an
    /// id prefix. Falling through would let `restore open 2` reopen entry 1 whenever entry 1's id happens to
    /// start with a 2, which is a wrong session reopened on a typo. Everything else is an exact or prefix
    /// match on the ENTRY id, then on the id of the closed session or workspace the entry holds — a full
    /// UUID carries dashes, so nothing addressable is lost.
    public static func resolve(_ target: String, items: [RecentClosedItem]) -> TargetResolution {
        let needle = target.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return .notFound }
        if let index = Int(needle) {
            guard index >= 1, index <= items.count else { return .notFound }
            return .resolved(items[index - 1].id)
        }
        let byEntry = ControlResolve.resolve(needle, candidates: items.map(\.id), active: nil)
        guard case .notFound = byEntry else { return byEntry }
        let lowered = needle.lowercased()
        let hits = items.filter { item in
            let ids = [item.session?.snapshot.id, item.workspace?.snapshot.id].compactMap { $0?.uuidString.lowercased() }
            return ids.contains { $0.hasPrefix(lowered) }
        }
        switch hits.count {
        case 0: return .notFound
        case 1: return .resolved(hits[0].id)
        default: return .ambiguous(hits.map(\.id))
        }
    }
}

public struct RecentClosedState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var items: [RecentClosedItem]

    public init(version: Int = RecentClosedState.currentVersion, items: [RecentClosedItem] = []) {
        self.version = version
        self.items = items
    }
}

public struct RecentClosedStore: Sendable {
    private let directory: URL
    private let fileName: String
    private let limit: Int

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    public init(directory: URL = PersistenceStore.defaultDirectory,
                fileName: String = "recent-closed.json",
                limit: Int = 20) {
        self.directory = directory
        self.fileName = fileName
        self.limit = max(1, limit)
    }

    public func load() -> [RecentClosedItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let state = try? JSONDecoder().decode(RecentClosedState.self, from: data) else { return [] }
        guard state.version == RecentClosedState.currentVersion else { return [] }
        return Array(state.items.prefix(limit))
    }

    public func record(_ item: RecentClosedItem) {
        var items = load()
        items.removeAll { existing in
            if existing.id == item.id { return true }
            switch (existing.kind, item.kind) {
            case (.session, .session):
                return existing.session?.snapshot.id == item.session?.snapshot.id
            case (.workspace, .workspace):
                return existing.workspace?.snapshot.id == item.workspace?.snapshot.id
            default:
                return false
            }
        }
        items.insert(item, at: 0)
        save(Array(items.prefix(limit)))
    }

    public func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    public func clear() {
        save([])
    }

    private func save(_ items: [RecentClosedItem]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(RecentClosedState(items: items)).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("agterm: save recent closed failed: %@", String(describing: error))
        }
    }
}
