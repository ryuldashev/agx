import Foundation

/// Append-only journal of what drove the UI: modifier chords the key monitor saw, built-in actions and
/// their origin (keymap / palette / control socket), and the pane-state flips they caused. One JSON object
/// per line in `<state dir>/journal.jsonl`, rotated once to `journal.1.jsonl` past `maxBytes`.
///
/// Exists to replace guesswork: "the scratch pane covered a live agent — was that ⌘J on a Cyrillic layout, a
/// stray `agtermctl session scratch on`, or a palette row?" is answered by `tail`ing the file, not by
/// reconstructing keystrokes from what landed in a shell. Plain typing (no ⌘/⌃) is never recorded.
///
/// Writes are fire-and-forget on a serial queue and never throw; a journal that cannot be written is silent.
public final class ActionJournal: @unchecked Sendable {
    public static let shared = ActionJournal()

    public static let fileName = "journal.jsonl"
    public static let rotatedFileName = "journal.1.jsonl"

    private let queue = DispatchQueue(label: "agterm.action-journal", qos: .utility)
    private var directory: URL?
    private var observer: (@Sendable (String, [String: String]) -> Void)?
    private let maxBytes: Int
    private let now: () -> Date
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(directory: URL? = nil, maxBytes: Int = 8 * 1024 * 1024, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.maxBytes = maxBytes
        self.now = now
    }

    /// Point the journal at the state directory (the same `AGTERM_STATE_DIR` override the stores use).
    /// Until configured, `log` drops records — a test host or a CLI process never journals by accident.
    public func configure(directory: URL) {
        queue.sync { self.directory = directory }
    }

    public var fileURL: URL? { queue.sync { directory?.appendingPathComponent(Self.fileName) } }

    /// One listener sees every record on the journal's queue, configured or not — the discovery map is
    /// derived from the same records the file gets, so the two can never disagree.
    public func setObserver(_ observer: (@Sendable (String, [String: String]) -> Void)?) {
        queue.sync { self.observer = observer }
    }

    /// Record one event. `kind` names the layer (`key`, `action`, `control`, `state`); `fields` are flat
    /// string pairs — keep them short, this is a grep target, not a data model.
    public func log(_ kind: String, _ fields: [String: String] = [:]) {
        let stamp = formatter.string(from: now())
        queue.async { [self] in
            observer?(kind, fields)
            guard let directory else { return }
            var record: [String: String] = fields
            record["ts"] = stamp
            record["kind"] = kind
            guard var data = try? JSONEncoder.sortedKeys.encode(record) else { return }
            data.append(0x0A)
            append(data, in: directory)
        }
    }

    /// Block until every record queued so far is on disk. Tests and shutdown paths only.
    public func flush() { queue.sync {} }

    private func append(_ data: Data, in directory: URL) {
        let fm = FileManager.default
        let url = directory.appendingPathComponent(Self.fileName)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size >= maxBytes {
            let rotated = directory.appendingPathComponent(Self.rotatedFileName)
            try? fm.removeItem(at: rotated)
            try? fm.moveItem(at: url, to: rotated)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}

private extension JSONEncoder {
    static let sortedKeys: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}
