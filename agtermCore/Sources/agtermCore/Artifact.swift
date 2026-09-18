import Foundation

/// A file (or URL) an agent SHOWED the user — `open x.pdf`, `agx reader plan.md`, a file sent to the
/// phone, or an explicit `agx artifact add`. Not a file it merely wrote: build intermediates, logs and
/// source edits never enter the index, so the list stays the user's outcomes and nothing else.
/// Size, mtime and existence are read from disk at display time, never stored: a PDF regenerated in place
/// keeps its row current.
public struct Artifact: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// An absolute, standardized path, or the URL string for `.url`. The dedup key.
    public var path: String
    public var kind: ArtifactKind
    /// The caller's caption; nil shows the basename.
    public var title: String?
    public var firstSeen: Date
    public var lastSeen: Date
    /// How many times it was shown.
    public var count: Int
    public var source: ArtifactSource
    /// The agx session that showed it, when known. Names are frozen at record time: the session may be
    /// closed by the time the row is read.
    public var sessionID: UUID?
    public var sessionName: String?
    public var workspaceName: String?
    /// Where the showing command ran, so a relative row still says which project it belongs to.
    public var cwd: String?
    /// The agent transcript id (a Claude Code session uuid) — the way back to the conversation.
    public var agentSession: String?
    public var pinned: Bool
    /// Hidden rows stay in the index (a later show unhides them) and are listed only on request.
    public var hidden: Bool

    public init(id: UUID = UUID(), path: String, kind: ArtifactKind, title: String? = nil,
                firstSeen: Date, lastSeen: Date, count: Int = 1, source: ArtifactSource,
                sessionID: UUID? = nil, sessionName: String? = nil, workspaceName: String? = nil,
                cwd: String? = nil, agentSession: String? = nil, pinned: Bool = false, hidden: Bool = false) {
        self.id = id
        self.path = path
        self.kind = kind
        self.title = title
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
        self.source = source
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.workspaceName = workspaceName
        self.cwd = cwd
        self.agentSession = agentSession
        self.pinned = pinned
        self.hidden = hidden
    }

    /// The caption or the basename (a URL's last path component, or its host).
    public var displayName: String {
        if let title = title?.trimmedOrNil { return title }
        switch kind {
        case .file:
            return (path as NSString).lastPathComponent
        case .url:
            guard let url = URL(string: path) else { return path }
            let last = url.lastPathComponent
            if !last.isEmpty, last != "/" { return last }
            return url.host ?? path
        }
    }

    /// The lowercase extension for a file, `url` for a link, `-` when there is none.
    public var typeLabel: String {
        switch kind {
        case .url: return "url"
        case .file:
            let ext = (path as NSString).pathExtension.lowercased()
            return ext.isEmpty ? "-" : ext
        }
    }

    public var category: ArtifactCategory { ArtifactCategory.of(self) }
}

public enum ArtifactKind: String, Codable, Sendable, CaseIterable {
    case file
    case url
}

/// How the artifact entered the index. `open`/`reader`/`sendfile` come from the Claude Code hook,
/// `manual` from `agx artifact add`, `backfill` from the transcript scan.
public enum ArtifactSource: String, Codable, Sendable, CaseIterable {
    case open
    case reader
    case sendfile
    case manual
    case backfill
}

/// The filter buckets the window offers, derived from the extension so nothing is stored.
public enum ArtifactCategory: String, Codable, Sendable, CaseIterable {
    case pdf
    case image
    case document
    case sheet
    case slides
    case media
    case code
    case url
    case other

    public static func of(_ artifact: Artifact) -> ArtifactCategory {
        if artifact.kind == .url { return .url }
        switch artifact.typeLabel {
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "tiff", "bmp": return .image
        case "md", "markdown", "txt", "rtf", "docx", "doc", "pages", "html", "htm", "epub": return .document
        case "xlsx", "xls", "csv", "tsv", "numbers": return .sheet
        case "pptx", "ppt", "key": return .slides
        case "mp4", "mov", "m4a", "mp3", "wav", "webm": return .media
        case "py", "swift", "js", "ts", "sh", "json", "yaml", "yml", "toml", "sql", "rb", "go", "rs": return .code
        default: return .other
        }
    }

    public var title: String {
        switch self {
        case .pdf: return "PDF"
        case .image: return "Images"
        case .document: return "Documents"
        case .sheet: return "Sheets"
        case .slides: return "Slides"
        case .media: return "Media"
        case .code: return "Code"
        case .url: return "Links"
        case .other: return "Other"
        }
    }
}

/// Limits and normalization shared by `artifact.add`, the hook and the backfill, so every entry point
/// refuses the same input with the same words and stores the same key for the same file.
public enum ArtifactPolicy {
    public static let maxItems = 2000
    public static let maxTitleLength = 200
    public static let maxPathLength = 4096

    /// The stored key for a raw reference: an `http(s)`/`file` URL stays a URL (a `file:` URL becomes its
    /// path); `~` expands; a relative path resolves against `cwd` and is refused without one. The result is
    /// standardized (`..` and `.` folded), never resolved through symlinks — the user's own path spelling
    /// is what they will recognize.
    public static func normalize(_ raw: String, cwd: String?) -> (path: String, kind: ArtifactKind)? {
        guard let text = raw.trimmedOrNil, text.count <= maxPathLength, !containsControlCharacters(text) else {
            return nil
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" { return (text, .url) }
            if scheme == "file" { return (url.standardizedFileURL.path, .file) }
        }
        var path = text
        if path.hasPrefix("~") { path = (path as NSString).expandingTildeInPath }
        if !path.hasPrefix("/") {
            guard let cwd = cwd?.trimmedOrNil, cwd.hasPrefix("/") else { return nil }
            path = (cwd as NSString).appendingPathComponent(path)
        }
        return ((path as NSString).standardizingPath, .file)
    }

    /// Why a non-empty `title` is unusable, or nil.
    public static func titleError(_ title: String) -> String? {
        if title.count > maxTitleLength { return "title too long (max \(maxTitleLength) characters)" }
        if containsControlCharacters(title) { return "title must not contain control characters" }
        return nil
    }

    static func containsControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }
}

/// One showing, as `artifact.add` carries it after validation. The index folds it into an existing row
/// with the same key or appends a new one.
public struct ArtifactRecord: Equatable, Sendable {
    public var path: String
    public var kind: ArtifactKind
    public var title: String?
    public var source: ArtifactSource
    public var seen: Date
    public var sessionID: UUID?
    public var sessionName: String?
    public var workspaceName: String?
    public var cwd: String?
    public var agentSession: String?

    public init(path: String, kind: ArtifactKind, title: String? = nil, source: ArtifactSource,
                seen: Date = Date(), sessionID: UUID? = nil, sessionName: String? = nil,
                workspaceName: String? = nil, cwd: String? = nil, agentSession: String? = nil) {
        self.path = path
        self.kind = kind
        self.title = title
        self.source = source
        self.seen = seen
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.workspaceName = workspaceName
        self.cwd = cwd
        self.agentSession = agentSession
    }
}

/// The pure list: dedup, pin/hide, lookup, ordering, pruning. `ArtifactLibrary` owns one and persists it.
public struct ArtifactIndex: Equatable, Sendable {
    public private(set) var items: [Artifact]

    public init(items: [Artifact] = []) {
        self.items = items
    }

    /// Fold a showing in. A row with the same key gains the newer `lastSeen`, keeps the earlier
    /// `firstSeen`, counts one more, and — when this showing is the newest — takes the new session,
    /// title and source and comes out of hiding, since the user was just shown it again. A backfilled
    /// showing older than the row never overrides what a live hook recorded.
    @discardableResult
    public mutating func record(_ record: ArtifactRecord) -> (artifact: Artifact, deduplicated: Bool) {
        if let index = items.firstIndex(where: { $0.path == record.path }) {
            var row = items[index]
            row.count += 1
            row.firstSeen = min(row.firstSeen, record.seen)
            if record.seen >= row.lastSeen {
                row.lastSeen = record.seen
                row.source = record.source
                if let title = record.title { row.title = title }
                if record.sessionID != nil || record.sessionName != nil {
                    row.sessionID = record.sessionID
                    row.sessionName = record.sessionName
                    row.workspaceName = record.workspaceName
                }
                if let cwd = record.cwd { row.cwd = cwd }
                if let agentSession = record.agentSession { row.agentSession = agentSession }
                if record.source != .backfill { row.hidden = false }
            } else if row.title == nil, let title = record.title {
                row.title = title
            }
            items[index] = row
            return (row, true)
        }
        let row = Artifact(path: record.path, kind: record.kind, title: record.title,
                           firstSeen: record.seen, lastSeen: record.seen, count: 1, source: record.source,
                           sessionID: record.sessionID, sessionName: record.sessionName,
                           workspaceName: record.workspaceName, cwd: record.cwd, agentSession: record.agentSession)
        items.append(row)
        prune()
        return (row, false)
    }

    public func item(withID id: UUID) -> Artifact? { items.first { $0.id == id } }

    /// A full id, a unique id prefix, or the exact stored path / URL.
    public func resolve(_ target: String) -> Artifact? {
        let text = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let id = UUID(uuidString: text), let item = item(withID: id) { return item }
        if let exact = items.first(where: { $0.path == text }) { return exact }
        let upper = text.uppercased()
        let prefixed = items.filter { $0.id.uuidString.hasPrefix(upper) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }

    @discardableResult
    public mutating func setPinned(_ pinned: Bool, id: UUID) -> Artifact? {
        update(id) { $0.pinned = pinned }
    }

    @discardableResult
    public mutating func setHidden(_ hidden: Bool, id: UUID) -> Artifact? {
        update(id) { $0.hidden = hidden }
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Artifact? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    private mutating func update(_ id: UUID, _ body: (inout Artifact) -> Void) -> Artifact? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        body(&items[index])
        return items[index]
    }

    /// Pinned first, then newest showing first. `query` matches the caption, path, session and workspace
    /// names, case-insensitively, every whitespace-separated term having to hit.
    public func filtered(query: String = "", workspace: String? = nil, category: ArtifactCategory? = nil,
                         session: UUID? = nil, includeHidden: Bool = false) -> [Artifact] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            if !includeHidden, item.hidden { return false }
            if let workspace, item.workspaceName?.caseInsensitiveCompare(workspace) != .orderedSame { return false }
            if let category, item.category != category { return false }
            if let session, item.sessionID != session { return false }
            guard !terms.isEmpty else { return true }
            let haystack = [item.displayName, item.path, item.sessionName ?? "", item.workspaceName ?? ""]
                .joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
        .sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.lastSeen > rhs.lastSeen
        }
    }

    /// The distinct workspace names present, for the filter picker.
    public var workspaceNames: [String] {
        Array(Set(items.compactMap { $0.workspaceName?.trimmedOrNil })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Keep the list at `ArtifactPolicy.maxItems`: hidden rows go first, then the oldest showings;
    /// pinned rows never go.
    private mutating func prune() {
        guard items.count > ArtifactPolicy.maxItems else { return }
        let victims = items.filter { !$0.pinned }
            .sorted { lhs, rhs in
                if lhs.hidden != rhs.hidden { return lhs.hidden }
                return lhs.lastSeen < rhs.lastSeen
            }
            .prefix(items.count - ArtifactPolicy.maxItems)
            .map(\.id)
        let gone = Set(victims)
        items.removeAll { gone.contains($0.id) }
    }
}

/// The persisted form at `<stateDirectory>/artifacts.json`, version-gated like `ScheduledSessionsFile`.
public struct ArtifactsFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var items: [Artifact]

    public init(version: Int = ArtifactsFile.currentVersion, items: [Artifact] = []) {
        self.version = version
        self.items = items
    }
}

/// JSON load/save. A missing, corrupt or foreign-version file loads as empty; saves are atomic.
public struct ArtifactStore: Sendable {
    public static let fileName = "artifacts.json"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func load() -> [Artifact] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ArtifactsFile.self, from: data),
              file.version == ArtifactsFile.currentVersion else { return [] }
        return file.items
    }

    public func save(_ items: [Artifact]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ArtifactsFile(items: items)).write(to: fileURL, options: .atomic)
    }
}

/// Owns the index for the app's lifetime: loads it once, saves after every mutation, and is what the
/// window observes. Host-free so the whole record → list → pin → prune cycle is tested without AppKit.
@MainActor
@Observable
public final class ArtifactLibrary {
    public private(set) var index: ArtifactIndex
    @ObservationIgnored private let store: ArtifactStore
    /// Called after a save fails; the app logs it. The in-memory list is kept either way.
    @ObservationIgnored public var saveFailed: ((Error) -> Void)?

    public init(directory: URL) {
        store = ArtifactStore(directory: directory)
        index = ArtifactIndex(items: store.load())
    }

    public var items: [Artifact] { index.items }

    public func reload() {
        index = ArtifactIndex(items: store.load())
    }

    @discardableResult
    public func record(_ record: ArtifactRecord) -> (artifact: Artifact, deduplicated: Bool) {
        let result = index.record(record)
        save()
        return result
    }

    @discardableResult
    public func setPinned(_ pinned: Bool, id: UUID) -> Artifact? {
        defer { save() }
        return index.setPinned(pinned, id: id)
    }

    @discardableResult
    public func setHidden(_ hidden: Bool, id: UUID) -> Artifact? {
        defer { save() }
        return index.setHidden(hidden, id: id)
    }

    @discardableResult
    public func remove(id: UUID) -> Artifact? {
        defer { save() }
        return index.remove(id: id)
    }

    public func resolve(_ target: String) -> Artifact? { index.resolve(target) }

    private func save() {
        do { try store.save(index.items) } catch { saveFailed?(error) }
    }
}

/// The wire projection of one row, for `artifact.add`'s echo and `artifact.list`. `exists` and `size`
/// are the host's disk reads, absent for a URL.
public struct ControlArtifactNode: Codable, Sendable, Equatable {
    public let id: String
    public let path: String
    public let kind: String
    public let name: String
    public let title: String?
    public let type: String
    public let category: String
    /// ISO 8601 with the local offset.
    public let seen: String
    public let firstSeen: String
    public let count: Int
    public let source: String
    public let session: String?
    public let sessionID: String?
    public let workspace: String?
    public let cwd: String?
    public let agentSession: String?
    public let pinned: Bool
    public let hidden: Bool
    public let exists: Bool?
    public let size: Int?

    public init(id: String, path: String, kind: String, name: String, title: String?, type: String, category: String,
                seen: String, firstSeen: String, count: Int, source: String, session: String?, sessionID: String?,
                workspace: String?, cwd: String?, agentSession: String?, pinned: Bool, hidden: Bool,
                exists: Bool?, size: Int?) {
        self.id = id
        self.path = path
        self.kind = kind
        self.name = name
        self.title = title
        self.type = type
        self.category = category
        self.seen = seen
        self.firstSeen = firstSeen
        self.count = count
        self.source = source
        self.session = session
        self.sessionID = sessionID
        self.workspace = workspace
        self.cwd = cwd
        self.agentSession = agentSession
        self.pinned = pinned
        self.hidden = hidden
        self.exists = exists
        self.size = size
    }

    public static func project(_ item: Artifact, exists: Bool? = nil, size: Int? = nil,
                               timeZone: TimeZone = .current) -> ControlArtifactNode {
        ControlArtifactNode(id: item.id.uuidString, path: item.path, kind: item.kind.rawValue, name: item.displayName,
                            title: item.title, type: item.typeLabel, category: item.category.rawValue,
                            seen: ControlISO8601.string(item.lastSeen, timeZone: timeZone),
                            firstSeen: ControlISO8601.string(item.firstSeen, timeZone: timeZone),
                            count: item.count, source: item.source.rawValue, session: item.sessionName,
                            sessionID: item.sessionID?.uuidString, workspace: item.workspaceName, cwd: item.cwd,
                            agentSession: item.agentSession, pinned: item.pinned, hidden: item.hidden,
                            exists: exists, size: size)
    }
}

/// What `artifact.add` hands the host after the dispatcher normalized the key and checked the title.
public struct ControlArtifactAddOptions: Equatable, Sendable {
    public let path: String
    public let kind: ArtifactKind
    public let title: String?
    public let source: ArtifactSource
    public let seen: Date?
    /// The showing session (`--session`), resolved app-side; nil records no session.
    public let session: String?
    public let cwd: String?
    public let agentSession: String?

    public init(path: String, kind: ArtifactKind, title: String?, source: ArtifactSource, seen: Date?,
                session: String?, cwd: String?, agentSession: String?) {
        self.path = path
        self.kind = kind
        self.title = title
        self.source = source
        self.seen = seen
        self.session = session
        self.cwd = cwd
        self.agentSession = agentSession
    }
}

public struct ControlArtifactListOptions: Equatable, Sendable {
    public let query: String?
    public let workspace: String?
    public let category: ArtifactCategory?
    public let session: String?
    public let includeHidden: Bool
    public let limit: Int?

    public init(query: String?, workspace: String?, category: ArtifactCategory?, session: String?,
                includeHidden: Bool, limit: Int?) {
        self.query = query
        self.workspace = workspace
        self.category = category
        self.session = session
        self.includeHidden = includeHidden
        self.limit = limit
    }
}
