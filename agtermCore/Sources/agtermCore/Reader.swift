import Foundation

/// The markdown reader in a session's SPLIT pane: which file it shows. The reader takes the right pane's
/// slot — the split is shown if it was not, and the pane renders the document instead of its shell — so it
/// sits in the native split with its divider, ratio and focus rules, rather than floating over the session.
/// NOT persisted: a reader is a view onto work in flight, and the file may be gone by the next launch.
public struct ReaderSpec: Equatable, Sendable {
    /// Absolute path of the markdown file, resolved by the CLI against the caller's cwd.
    public var path: String
    /// The caller's requested WIDTH share of the pane, applied to the split ratio on open; nil keeps the
    /// split's own ratio (or `ReaderLayout.defaultSizePercent` for a split the reader had to show).
    public var sizePercent: Int?

    public init(path: String, sizePercent: Int? = nil) {
        self.path = path
        self.sizePercent = sizePercent
    }
}

/// The reader's geometry rules, host-free so the dispatcher and the store agree on them.
public enum ReaderLayout {
    public static let defaultSizePercent = 45
    /// Width bounds: below the floor a column of prose is unreadable, above the cap the shell beside it is.
    public static let minSizePercent = 20
    public static let maxSizePercent = 80

    public static func clampSizePercent(_ percent: Int) -> Int {
        min(maxSizePercent, max(minSizePercent, percent))
    }

    /// The split divider's PRIMARY-pane fraction that leaves the reader `percent` of the pane.
    public static func splitRatio(forSizePercent percent: Int) -> Double {
        1 - Double(clampSizePercent(percent)) / 100
    }
}

/// The reader as projected into the `tree` response; present only while one is up. The read side of
/// `session.reader.open`; poll-only, no event announces it. Its width is the session's `splitRatio`.
public struct ControlReaderNode: Codable, Sendable, Equatable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

/// Error strings for `session.reader.*`, owned once so the dispatcher, the host and the tests agree.
public enum ReaderError {
    public static let noReader = "no reader"
    public static let requiresPath = "session.reader.open requires a path"
    public static let unreadable = "cannot read file"
}
