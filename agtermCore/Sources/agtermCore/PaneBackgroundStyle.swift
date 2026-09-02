/// How a split pane restyles the background art it shares with the primary pane: flip it horizontally and
/// fade it, so the two panes read as one drawing cut by the divider instead of the same corner mark twice.
/// Host-free formatting only — the flipped PNG is rendered app-side (libghostty has no mirror key), and
/// `WatermarkConfig` turns the style into the `background-image*` lines.
public struct PaneBackgroundStyle: Codable, Sendable, Equatable {
    /// Mirror the image and its anchor across the vertical axis.
    public var mirror: Bool
    /// Multiplier on `background-image-opacity`, `0...1`: the split pane is the passenger and its art
    /// should not compete with the focused one.
    public var fade: Double

    /// The style of a pane that inherits the primary pane's background untouched.
    public static let identity = PaneBackgroundStyle(mirror: false, fade: 1)

    public init(mirror: Bool, fade: Double) {
        self.mirror = mirror
        self.fade = Self.isValidFade(fade) ? fade : 1
    }

    /// Valid `fade`: finite and within `0...1`, matching `WatermarkConfig.isValidOpacity`.
    public static func isValidFade(_ fade: Double) -> Bool { fade.isFinite && fade >= 0 && fade <= 1 }

    public var isIdentity: Bool { self == .identity }

    /// The anchor this style's image belongs at, given the unstyled one.
    public func anchor(_ position: BackgroundWatermark.Position) -> BackgroundWatermark.Position {
        mirror ? position.horizontallyMirrored : position
    }

    /// The faded `background-image-opacity`, given the unstyled one (nil = ghostty's 1.0 default). Returns
    /// nil only when the result IS that default, so an unfaded pane emits no opacity line.
    public func faded(_ opacity: Double?) -> Double? {
        let value = (opacity ?? 1) * fade
        return value == 1 ? nil : value
    }
}
