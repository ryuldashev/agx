import Foundation

/// The markdown reader panel over a session: which file it shows and where it sits. Its own slot beside the
/// overlay's, so a document can stay up while a HUD reports progress or a program overlay runs. NOT
/// persisted: a reader is a view onto work in flight, and the file may be gone by the next launch.
public struct ReaderSpec: Equatable, Sendable {
    /// Absolute path of the markdown file, resolved by the CLI against the caller's cwd.
    public var path: String
    /// Which of the pane's nine anchors the panel sits on, the same set `session.hud` and
    /// `session.background` take.
    public var position: HudPosition
    /// Share of the pane's WIDTH the panel occupies, within `ReaderLayout.clampSizePercent`.
    public var sizePercent: Int

    public init(path: String, position: HudPosition = ReaderLayout.defaultPosition,
                sizePercent: Int = ReaderLayout.defaultSizePercent) {
        self.path = path
        self.position = position
        self.sizePercent = sizePercent
    }
}

/// The reader panel's geometry rules, host-free so the dispatcher and the deck agree on them.
public enum ReaderLayout {
    /// Right-hand side: a document beside the pane rather than over its prompt.
    public static let defaultPosition = HudPosition.centerRight
    public static let defaultSizePercent = 45
    /// Width bounds: below the floor a column of prose is unreadable, above the cap the panel is a cover and
    /// the session it documents disappears — `session.overlay` exists for that.
    public static let minSizePercent = 20
    public static let maxSizePercent = 80
    /// The panel runs nearly the pane's full height; `OverlayPanelStyle` centers a fraction this large on
    /// the vertical axis whatever the anchor's row, leaving a small margin top and bottom.
    public static let heightPercent = 92

    public static func clampSizePercent(_ percent: Int) -> Int {
        min(maxSizePercent, max(minSizePercent, percent))
    }
}

/// The reader panel as projected into the `tree` response; present only while one is up. The read side of
/// `session.reader.open`; poll-only, no event announces it.
public struct ControlReaderNode: Codable, Sendable, Equatable {
    public let path: String
    /// The EFFECTIVE anchor, defaults included, so a caller can round-trip what `tree` gave it.
    public let position: String
    /// The EFFECTIVE width share, after `ReaderLayout.clampSizePercent`.
    public let sizePercent: Int

    public init(path: String, position: String, sizePercent: Int) {
        self.path = path
        self.position = position
        self.sizePercent = sizePercent
    }
}

/// Error strings for `session.reader.*`, owned once so the dispatcher, the host and the tests agree.
public enum ReaderError {
    public static let noReader = "no reader"
    public static let requiresPath = "session.reader.open requires a path"
    public static let unreadable = "cannot read file"
}
