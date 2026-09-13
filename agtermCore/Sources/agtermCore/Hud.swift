import Foundation

/// The message a control client posts over a session while it prepares something. `position` takes its
/// default when the caller omits it, so a decoded spec always carries an effective value the read-back can
/// report; `spinner` is optional throughout, its absence BEING the effective value.
public struct HudSpec: Codable, Equatable, Sendable {
    public let message: String
    public let detail: String?
    /// The spinner's style, nil for a static panel. An enum rather than a flag so `hud update` can switch
    /// the look in place.
    public let spinner: HudSpinner?
    /// `#rrggbb` plate behind the panel; nil draws the message with no plate at all, over the session.
    public let backgroundColor: String?
    /// `#rrggbb` for the panel's TEXT; nil keeps the terminal foreground.
    public let textColor: String?
    /// Caller override for the panel's share of the pane WIDTH; nil lets `HudLayout` measure it from the
    /// message. There is no height counterpart — `HudLayout.heightPercent` owns why.
    public let sizePercent: Int?
    public let position: HudPosition

    /// Cap on `message` and `detail` each, enforced by the dispatcher in `HudLayout.textLength`'s unit. The
    /// panel wraps at `HudLayout.maxColumns` and is clamped to `HudLayout.maxSizePercent`, so longer text
    /// cannot be shown.
    public static let maxTextLength = 256

    public init(message: String, detail: String? = nil, spinner: HudSpinner? = nil,
                backgroundColor: String? = nil, textColor: String? = nil,
                sizePercent: Int? = nil, position: HudPosition = .defaultPosition) {
        self.message = message
        self.detail = detail
        self.spinner = spinner
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.sizePercent = sizePercent
        self.position = position
    }

    enum CodingKeys: String, CodingKey {
        case message, detail, spinner, backgroundColor, textColor, sizePercent, position
    }

    /// A copy carrying `color` in place of this spec's own background. `AppStore.updateHud` holds the LIVE
    /// panel's color across an update with it: the slot's `overlayBackgroundColor` is set once at open, so a
    /// stored spec carrying any other value would report a color the panel does not paint.
    func withBackgroundColor(_ color: String?) -> HudSpec {
        HudSpec(message: message, detail: detail, spinner: spinner, backgroundColor: color,
                textColor: textColor, sizePercent: sizePercent, position: position)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        spinner = try c.decodeIfPresent(HudSpinner.self, forKey: .spinner)
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        sizePercent = try c.decodeIfPresent(Int.self, forKey: .sizePercent)
        position = try c.decodeIfPresent(HudPosition.self, forKey: .position) ?? .defaultPosition
    }
}

/// The animated glyph a spinning panel shows beside its message. Every case owns its own frames and tick
/// rate, so a style is one edit here. `CaseIterable` so dispatcher validation and CLI help derive from the
/// cases.
///
/// Every frame must be ONE Unicode scalar that renders ONE column: the panel counts scalars rather than
/// display width (`HudLayout.cellCount` states why), and `HudLayout.spinnerWidth` reserves exactly two
/// cells, so a double-width glyph — any emoji, most of the CJK blocks — would overflow the frame.
public enum HudSpinner: String, Codable, CaseIterable, Sendable {
    /// ASCII, so it renders in any font. The default for that reason.
    case bar
    case braille
    case circle
    case blocks
    /// A dot that blinks off rather than animating, for a panel that sits up for minutes.
    case dot

    /// The style a caller who asks for a spinner without naming one gets.
    public static let defaultStyle = HudSpinner.bar

    /// The read-back's spelling for a panel with NO spinner, and an ACCEPTED input on both the socket and
    /// the CLI: it is what `tree` reports, so a caller must be able to echo it straight back. A raw value no
    /// case uses, so it can never collide with a style name.
    public static let noneName = "none"

    /// The style names pipe-joined — the prose form for docs naming what the styles ARE.
    public static var validNamesList: String { allCases.map(\.rawValue).joined(separator: "|") }

    /// Everything a caller may PASS, `noneName` included, pipe-joined: the control server's rejection
    /// message. It lists more than `validNamesList` because `none` is accepted and is not a style — a
    /// rejection naming only the styles would refuse a value the dispatcher takes.
    public static var acceptedNamesList: String {
        (allCases.map(\.rawValue) + [noneName]).joined(separator: "|")
    }

    /// The same accepted set comma-joined — the prose form for `agtermctl --spinner-style` help and its
    /// local rejection, which must accept exactly what the socket does.
    public static var acceptedNamesPhrase: String {
        (allCases.map(\.rawValue) + [noneName]).joined(separator: ", ")
    }

    public var frames: [String] {
        switch self {
        case .bar: return ["|", "/", "-", "\\"]
        case .braille: return ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        case .circle: return ["◐", "◓", "◑", "◒"]
        case .blocks: return ["▁", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃"]
        // the blank half of the blink is a NO-BREAK SPACE, not a space, so a trimming layout cannot collapse
        // it: it renders as one blank column and counts as one scalar, so the glyph's cells stay reserved
        // and the message does not shift left on the off frame.
        case .dot: return ["●", "\u{00A0}"]
        }
    }

    /// Seconds between frames.
    public var interval: Double {
        switch self {
        case .bar: return 0.1
        case .braille, .blocks: return 0.08
        case .circle: return 0.12
        // a blink at an animation's rate reads as a flicker rather than a pulse
        case .dot: return 0.45
        }
    }
}

/// Where the panel sits in the pane: the nine anchors of a 3x3 grid, spelled exactly as
/// `BackgroundWatermark.Position` so `--position` means one thing across `session.background` and
/// `session.hud`. `CaseIterable` so dispatcher validation and CLI help derive from the cases rather than
/// repeating them.
public enum HudPosition: String, Codable, CaseIterable, Sendable {
    case topLeft = "top-left", topCenter = "top-center", topRight = "top-right"
    case centerLeft = "center-left", center, centerRight = "center-right"
    case bottomLeft = "bottom-left", bottomCenter = "bottom-center", bottomRight = "bottom-right"

    /// The bare spellings this enum shipped with, kept accepted so a caller written against `top`/`bottom`
    /// keeps working. They NORMALIZE: `parse` resolves them to the middle column, and the read-back reports
    /// that canonical name, which is what makes them aliases rather than a second vocabulary to maintain.
    /// Ordered rather than a dictionary because this list reaches help text and rejection messages, where
    /// hashed order would reshuffle between runs.
    static let aliases: [(name: String, position: HudPosition)] =
        [("top", .topCenter), ("bottom", .bottomCenter)]

    /// The placement a caller who omits `--position` gets. The ONE spelling of that default: the memberwise
    /// initializer, the lenient decoder, and the dispatcher all read it, so changing it is one edit.
    public static let defaultPosition = HudPosition.center

    /// Percent of the pane held clear at an edge the panel is anchored to, on EITHER axis; a `center` term
    /// ignores it on that axis. The margin is held only while the panel is small enough to leave room —
    /// `OverlayPanelStyle` centers instead of overhanging the pane, so a panel at or above
    /// `HudLayout.maxSizePercent` ignores the anchor on that axis entirely.
    public static let edgeMarginPercent = 10

    /// parse resolves a caller's spelling, aliases included. The ONE entry point for turning text into a
    /// position: the dispatcher, the CLI's local validation, and `init(from:)` all take it, so no path can
    /// accept a name another rejects.
    public static func parse(_ raw: String) -> HudPosition? {
        HudPosition(rawValue: raw) ?? aliases.first { $0.name == raw }?.position
    }

    /// Which row the anchor names.
    public var verticalBand: Band {
        switch self {
        case .topLeft, .topCenter, .topRight: return .leading
        case .centerLeft, .center, .centerRight: return .middle
        case .bottomLeft, .bottomCenter, .bottomRight: return .trailing
        }
    }

    /// Which column the anchor names.
    public var horizontalBand: Band {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: return .leading
        case .topCenter, .center, .bottomCenter: return .middle
        case .topRight, .centerRight, .bottomRight: return .trailing
        }
    }

    /// One axis' term of an anchor, so the two offsets are the same math over a different dimension. The app
    /// target's `OverlayPanelStyle` switches on it, which is why it crosses the module boundary.
    public enum Band: Sendable { case leading, middle, trailing }

    /// The canonical names pipe-joined — the prose form for docs and help naming what the anchors ARE.
    public static var validNamesList: String { validNames.joined(separator: "|") }

    /// The canonical names comma-joined.
    public static var validNamesPhrase: String { validNames.joined(separator: ", ") }

    /// Everything a caller may PASS, aliases included, pipe-joined: the control server's rejection message.
    /// It lists more than `validNamesList` because the aliases are accepted and are not canonical names — a
    /// rejection naming only the canonical set would refuse values the dispatcher takes, exactly as
    /// `HudSpinner.acceptedNamesList` covers `none`.
    public static var acceptedNamesList: String { acceptedNames.joined(separator: "|") }

    /// The same accepted set comma-joined — the prose form for `agtermctl --position` help and its local
    /// rejection, which must accept exactly what the socket does.
    public static var acceptedNamesPhrase: String { acceptedNames.joined(separator: ", ") }

    private static var validNames: [String] { allCases.map(\.rawValue) }
    private static var acceptedNames: [String] { validNames + aliases.map(\.name) }

    /// Decodes through `parse` rather than the synthesized raw-value initializer, so an alias survives a
    /// round trip through any coder and no decode path is stricter than the socket.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = HudPosition.parse(raw) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "unknown hud position: \(raw)")
        }
        self = parsed
    }
}

/// Terminal cell and pane dimensions the app measures for the sizing math. Double-backed, so no
/// CoreGraphics type crosses the module boundary.
public struct PaneMetrics: Equatable, Sendable {
    public let cellWidth: Double
    public let cellHeight: Double
    public let paneWidth: Double
    public let paneHeight: Double
    /// The terminal's own padding INSIDE the panel, per side: it holds no cells, so the percent math owes it
    /// room. Zero is the honest default for a caller that does not know the configured padding.
    public let paddingWidth: Double
    public let paddingHeight: Double

    public init(cellWidth: Double, cellHeight: Double, paneWidth: Double, paneHeight: Double,
                paddingWidth: Double = 0, paddingHeight: Double = 0) {
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.paneWidth = paneWidth
        self.paneHeight = paneHeight
        self.paddingWidth = paddingWidth
        self.paddingHeight = paddingHeight
    }
}

/// The panel's share of the pane on each axis. The two are measured separately — a HUD is a couple of lines
/// of text, so one percent across both made every panel as tall as it was wide — and travel together from
/// `HudLayout.panelSize` through the store to the deck, so no layer can hold half a size.
public struct HudPanelSize: Equatable, Sendable {
    public let widthPercent: Int
    public let heightPercent: Int

    public init(widthPercent: Int, heightPercent: Int) {
        self.widthPercent = widthPercent
        self.heightPercent = heightPercent
    }
}

/// Pure layout math for the HUD panel: message to a cell box, cell box to the pane percentages the overlay
/// slot reports and the native panel takes as its width budget. Host-free (`Int`/`Double` only) so
/// `swift test` covers it with no app host.
public enum HudLayout {
    /// Widest content line before wrapping; the frame padding sits outside it.
    public static let maxColumns = 60
    public static let maxSizePercent = 80
    public static let minSizePercent = 10

    /// Frame padding in cells, applied on both sides of the content.
    static let horizontalPadding = 2
    static let verticalPadding = 1
    /// Cells the spinner glyph and its trailing space claim, so turning the spinner on cannot rewrap text.
    static let spinnerWidth = 2

    /// clampSizePercent bounds a CALLER'S `--size-percent` into the same range the measured WIDTH produces.
    /// The maximum is the invariant `OverlayHudError.fullResize` states for `--full`, one layer down: a HUD
    /// is a message ABOUT a session and must never cover it, and 100 would do exactly that. The read-back
    /// reports the clamped value, so a caller sees what the panel actually took. Height takes no caller
    /// override at all — `heightPercent` owns why.
    public static func clampSizePercent(_ requested: Int) -> Int {
        min(max(requested, minSizePercent), maxSizePercent)
    }

    /// box returns the cell box the panel needs for `spec`: the wrapped content plus the frame padding. It
    /// decides how BIG the panel is (through `widthPercent` and `heightPercent`). Measured in `cellCount`'s
    /// unit.
    public static func box(for spec: HudSpec) -> (columns: Int, rows: Int) {
        let lines = bodyLines(for: spec)
        let widest = lines.map(cellCount).max() ?? 0
        let content = max(widest + (spec.spinner != nil ? spinnerWidth : 0), 1)
        return (columns: content + horizontalPadding * 2, rows: max(lines.count, 1) + verticalPadding * 2)
    }

    /// panelSize is the ONE place the two axes are decided together: the caller's `--size-percent` reaches
    /// the width alone, the height is always measured, and both come off a single `box` so they describe the
    /// same message. Every caller takes this rather than the two halves, which exist for the tests that pin
    /// each axis' own rules.
    public static func panelSize(for spec: HudSpec, pane: PaneMetrics) -> HudPanelSize {
        let box = box(for: spec)
        return HudPanelSize(widthPercent: spec.sizePercent ?? widthPercent(box: box, pane: pane),
                            heightPercent: heightPercent(box: box, pane: pane))
    }

    /// widthPercent returns the share of the pane's WIDTH the panel takes: the box's columns plus the
    /// terminal's own padding, clamped into `minSizePercent...maxSizePercent`. A pane with no measured width
    /// resolves to `maxSizePercent`: nothing is known to fit, so the panel takes the most room allowed.
    public static func widthPercent(box: (columns: Int, rows: Int), pane: PaneMetrics) -> Int {
        let needed = Double(max(box.columns, 0)) * pane.cellWidth + pane.paddingWidth * 2
        let measured = percent(needed, of: pane.paneWidth) ?? maxSizePercent
        return min(max(measured, minSizePercent), maxSizePercent)
    }

    /// heightPercent returns the share of the pane's HEIGHT the panel takes, and it is measured from the
    /// CONTENT alone — the box's rows plus the terminal's padding — never from a caller's `--size-percent`.
    /// A HUD is a message of two or three lines, so a caller-set height can only strand it in an empty box;
    /// the width is the one dimension worth overriding.
    ///
    /// Unlike the width this has NO minimum floor: the box already carries `verticalPadding` on both sides,
    /// so the smallest panel is as tall as its content and no taller. `minSizePercent` on this axis is
    /// exactly the square panel this split exists to remove. An unmeasured pane falls back to that floor
    /// rather than the width's maximum, for the same reason — 80% of a pane is a cover, not a message.
    public static func heightPercent(box: (columns: Int, rows: Int), pane: PaneMetrics) -> Int {
        let needed = Double(max(box.rows, 0)) * pane.cellHeight + pane.paddingHeight * 2
        guard let measured = percent(needed, of: pane.paneHeight) else { return minSizePercent }
        return min(max(measured, 1), maxSizePercent)
    }

    static func bodyLines(for spec: HudSpec) -> [String] {
        var lines = wrap(spec.message, columns: maxColumns)
        let detail = wrap(spec.detail ?? "", columns: maxColumns)
        guard !detail.isEmpty else { return lines }
        if !lines.isEmpty { lines.append("") }
        lines.append(contentsOf: detail)
        return lines
    }

    /// wrap breaks `text` into lines of at most `columns` cells, treating a newline as a hard break and
    /// splitting a word longer than the line. Blank lines are dropped, which is what keeps the single empty
    /// line in `bodyLines` unambiguous as the message/detail separator. The text is PRECOMPOSED first:
    /// macOS hands back decomposed (NFD) strings, and a combining accent counts as its own cell otherwise.
    static func wrap(_ text: String, columns: Int) -> [String] {
        let width = max(columns, 1)
        var lines: [String] = []
        for paragraph in text.precomposedStringWithCanonicalMapping.split(separator: "\n") {
            var current = ""
            for chunk in paragraph.split(separator: " ") {
                var word = String(chunk)
                while cellCount(word) > width {
                    if !current.isEmpty { lines.append(current); current = "" }
                    lines.append(String(String.UnicodeScalarView(word.unicodeScalars.prefix(width))))
                    word = String(String.UnicodeScalarView(word.unicodeScalars.dropFirst(width)))
                }
                if word.isEmpty { continue }
                if current.isEmpty {
                    current = word
                } else if cellCount(current) + 1 + cellCount(word) <= width {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = word
                }
            }
            if !current.isEmpty { lines.append(current) }
        }
        return lines
    }

    /// The unit the box counts in: Unicode scalars, not `String.count`'s grapheme clusters (one accented
    /// cluster is one Character but two scalars, a ZWJ emoji one against five) and not DISPLAY columns, so
    /// a double-width glyph (CJK, most emoji) is counted as one cell — accepted as an estimate of a width
    /// budget the native panel wraps inside anyway.
    static func cellCount(_ text: String) -> Int { text.unicodeScalars.count }

    /// textLength measures `HudSpec.maxTextLength`'s cap in the SAME unit and on the same precomposed form
    /// `wrap` lays the text out in, so the cap bounds what the panel actually has to fit.
    static func textLength(_ text: String) -> Int {
        cellCount(text.precomposedStringWithCanonicalMapping)
    }

    /// `size` as a whole percent of `available`, rounding UP so a panel never lands a cell short of its
    /// content. Nil when the pane is unmeasured; each axis picks its own fallback for that.
    private static func percent(_ size: Double, of available: Double) -> Int? {
        guard available > 0 else { return nil }
        return Int((size / available * 100).rounded(.up))
    }
}
