import Foundation

/// Host-free half of private sessions (ADR 0005): what an agent leaves on disk for one session id, found
/// and removed by EXACT id, the atomic history rewrite, and the pending list that survives a crash so the
/// next launch finishes what a hard-killed app could not. The app target owns when a sweep runs, the
/// abduco kill that precedes it, and the notification that reports it.
public enum PrivateSessionCleanup {
    public enum Agent: String, Codable, Sendable, CaseIterable {
        case claude, codex
    }

    /// One agent session to erase. `sessionID` is validated at construction: it comes from a hook's JSON,
    /// and a slash or `..` in it would turn an exact-id delete into a path walk.
    public struct Target: Codable, Hashable, Sendable {
        public var agent: Agent
        public var sessionID: String

        public init?(agent: Agent, sessionID: String) {
            guard Self.isValid(sessionID) else { return nil }
            self.agent = agent
            self.sessionID = sessionID
        }

        public static func isValid(_ id: String) -> Bool {
            !id.isEmpty && id.utf8.count <= 128
                && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }

    /// A closed (or crashed-away) private session whose files still have to go. Carries ids only — never a
    /// name, cwd or title, since the list itself sits on disk.
    public struct Pending: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var targets: [Target]
        public var createdAt: Date

        public init(id: UUID, targets: [Target], createdAt: Date = Date()) {
            self.id = id
            self.targets = targets
            self.createdAt = createdAt
        }
    }

    /// Where the agents keep their state. `home` is the user's home; `tmp` is Claude Code's per-user temp
    /// root (`/private/tmp/claude-<uid>`), whose per-cwd scratchpads and task outputs are keyed by session id.
    public struct Roots: Equatable, Sendable {
        public var home: String
        public var tmp: String

        public init(home: String, tmp: String) {
            self.home = home
            self.tmp = tmp
        }

        public static func standard(home: String = NSHomeDirectory(), uid: uid_t = getuid()) -> Roots {
            Roots(home: home, tmp: "/private/tmp/claude-\(uid)")
        }
    }

    public struct Report: Equatable, Sendable {
        public var removed: [String] = []
        public var droppedLines = 0
        public var failed: [String] = []

        public init(removed: [String] = [], droppedLines: Int = 0, failed: [String] = []) {
            self.removed = removed
            self.droppedLines = droppedLines
            self.failed = failed
        }

        public var isEmpty: Bool { removed.isEmpty && droppedLines == 0 && failed.isEmpty }

        /// One line for the log and the notification: counts, never paths.
        public var summary: String {
            var parts: [String] = []
            if !removed.isEmpty { parts.append("removed \(removed.count) file\(removed.count == 1 ? "" : "s")") }
            if droppedLines > 0 { parts.append("dropped \(droppedLines) history line\(droppedLines == 1 ? "" : "s")") }
            if !failed.isEmpty { parts.append("\(failed.count) could not be removed") }
            return parts.isEmpty ? "nothing left on disk" : parts.joined(separator: ", ")
        }

        mutating func merge(_ other: Report) {
            removed += other.removed
            droppedLines += other.droppedLines
            failed += other.failed
        }
    }

    // MARK: - Path plan

    /// A directory listed non-recursively for entries whose name matches the session id.
    struct Scan: Equatable {
        enum Match: Equatable {
            /// `<id>` itself or `<id>.<ext>`: the transcript, its sidecar directory, the archived `.jsonl.gz`.
            case stem
            /// `<id>…`: debug logs and todo files that append a suffix to the id.
            case prefix
            /// `…<id>…`: Codex rollouts, whose name is a timestamp plus the id.
            case contains
        }

        var directory: String
        var match: Match
        /// `nil` scans `directory` itself; a depth scans each subdirectory that many levels down instead
        /// (`projects/<cwd>/`, `sessions/<yyyy>/<mm>/<dd>/`).
        var depth: Int?
    }

    static func scans(for target: Target, roots: Roots) -> [Scan] {
        let home = roots.home
        switch target.agent {
        case .claude:
            return [
                Scan(directory: home + "/.claude/projects", match: .stem, depth: 1),
                Scan(directory: home + "/claude-archive/projects", match: .stem, depth: 1),
                Scan(directory: home + "/.claude/debug", match: .prefix, depth: nil),
                Scan(directory: home + "/.claude/todos", match: .prefix, depth: nil),
                Scan(directory: home + "/.claude/file-history", match: .stem, depth: nil),
                Scan(directory: home + "/.claude/session-env", match: .stem, depth: nil),
                Scan(directory: home + "/.claude/tasks", match: .stem, depth: nil),
                Scan(directory: roots.tmp, match: .stem, depth: 1),
            ]
        case .codex:
            return [Scan(directory: home + "/.codex/sessions", match: .contains, depth: 3)]
        }
    }

    /// The history file an agent appends every prompt to, and the key its lines carry the session id under.
    static func history(for agent: Agent, roots: Roots) -> (path: String, key: String) {
        switch agent {
        case .claude: return (roots.home + "/.claude/history.jsonl", "sessionId")
        case .codex: return (roots.home + "/.codex/history.jsonl", "session_id")
        }
    }

    static func matches(_ name: String, id: String, _ match: Scan.Match) -> Bool {
        switch match {
        case .stem: return name == id || name.hasPrefix(id + ".")
        case .prefix: return name.hasPrefix(id)
        case .contains: return name.contains(id)
        }
    }

    /// Every existing path a scan resolves to, in a stable order. Pure over the file system: nothing removed.
    static func paths(_ scan: Scan, id: String, fileManager: FileManager) -> [String] {
        var directories = [scan.directory]
        for _ in 0..<(scan.depth ?? 0) {
            directories = directories.flatMap { directory -> [String] in
                ((try? fileManager.contentsOfDirectory(atPath: directory)) ?? []).sorted()
                    .map { directory + "/" + $0 }
                    .filter { isDirectory($0, fileManager) }
            }
        }
        return directories.flatMap { directory -> [String] in
            ((try? fileManager.contentsOfDirectory(atPath: directory)) ?? []).sorted()
                .filter { matches($0, id: id, scan.match) }
                .map { directory + "/" + $0 }
        }
    }

    private static func isDirectory(_ path: String, _ fileManager: FileManager) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    // MARK: - History

    /// Drops every JSONL line whose `key` equals `sessionID`; a line that is not a JSON object is kept as is.
    /// Pure, so the rewrite's only I/O is one read and one atomic write.
    public static func filterHistory(_ text: String, dropping sessionID: String, key: String) -> (text: String, dropped: Int) {
        var kept: [Substring] = []
        var dropped = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let data = line.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object[key] as? String == sessionID {
                dropped += 1
            } else {
                kept.append(line)
            }
        }
        return (kept.joined(separator: "\n"), dropped)
    }

    /// Rewrites the history file without the session's lines: temp file beside it, then rename. A missing
    /// file or no matching line writes nothing.
    static func rewriteHistory(at path: String, dropping sessionID: String, key: String,
                               fileManager: FileManager) throws -> Int {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
        let (filtered, dropped) = filterHistory(text, dropping: sessionID, key: key)
        guard dropped > 0 else { return 0 }
        let temp = path + ".private-\(UUID().uuidString).tmp"
        try filtered.write(toFile: temp, atomically: false, encoding: .utf8)
        if rename(temp, path) != 0 {
            try? fileManager.removeItem(atPath: temp)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return dropped
    }

    // MARK: - Sweep

    /// Removes everything the targets left behind. Each path is deleted by exact id match, never by a wider
    /// glob; a path that fails to go is reported, not retried.
    public static func sweep(_ pending: Pending, roots: Roots, fileManager: FileManager = .default) -> Report {
        var report = Report()
        for target in pending.targets {
            for scan in scans(for: target, roots: roots) {
                for path in paths(scan, id: target.sessionID, fileManager: fileManager) {
                    do {
                        try fileManager.removeItem(atPath: path)
                        report.removed.append(path)
                    } catch {
                        report.failed.append(path)
                    }
                }
            }
            let history = history(for: target.agent, roots: roots)
            do {
                report.droppedLines += try rewriteHistory(at: history.path, dropping: target.sessionID,
                                                          key: history.key, fileManager: fileManager)
            } catch {
                report.failed.append(history.path)
            }
        }
        report.merge(sweepOwn(sessionID: pending.id, roots: roots, fileManager: fileManager))
        return report
    }

    /// agx's own per-session leftovers keyed by the agx session id: the usage file the bundled statusline
    /// writes under `~/.claude/agx-usage/`.
    static func sweepOwn(sessionID: UUID, roots: Roots, fileManager: FileManager) -> Report {
        var report = Report()
        let scan = Scan(directory: roots.home + "/.claude/agx-usage", match: .stem, depth: nil)
        for id in [sessionID.uuidString, sessionID.uuidString.lowercased()] {
            for path in paths(scan, id: id, fileManager: fileManager) {
                do {
                    try fileManager.removeItem(atPath: path)
                    report.removed.append(path)
                } catch {
                    report.failed.append(path)
                }
            }
        }
        return report
    }
}

/// The pending-cleanup list at `<stateDir>/private-cleanup.json`: a private session's targets are written
/// the moment they are known, so a crash between then and the close still leaves a record for the next
/// launch's sweeper. Empty once every sweep has run.
public struct PrivateCleanupStore: Sendable {
    private let directory: URL
    private let fileName: String

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    public init(directory: URL = PersistenceStore.defaultDirectory, fileName: String = "private-cleanup.json") {
        self.directory = directory
        self.fileName = fileName
    }

    public func load() -> [PrivateSessionCleanup.Pending] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? Self.decoder.decode([PrivateSessionCleanup.Pending].self, from: data) else { return [] }
        return items
    }

    /// Merges the entry for `pending.id` (ids already on disk are kept: a close that learned none must not
    /// forget what an earlier pin or launch recorded), or appends it. Returns what was written.
    @discardableResult
    public func upsert(_ pending: PrivateSessionCleanup.Pending) -> PrivateSessionCleanup.Pending {
        var items = load()
        var merged = pending
        if let index = items.firstIndex(where: { $0.id == pending.id }) {
            merged.targets = items[index].targets + pending.targets.filter { !items[index].targets.contains($0) }
            merged.createdAt = items[index].createdAt
            items.remove(at: index)
        }
        items.append(merged)
        save(items)
        return merged
    }

    public func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    private func save(_ items: [PrivateSessionCleanup.Pending]) {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
