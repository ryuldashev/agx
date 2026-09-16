import agtermCore
import AppKit
import SwiftUI

/// The passive `session.hud.*` panel, drawn natively over the session: a message in the system face at the
/// weight of a macOS notice, its detail a size down and dimmed, on Liquid Glass — or a solid plate when
/// the caller set `--background-color`. The glass takes the terminal's polarity as its color scheme, so it
/// is dark glass over a dark theme whatever the system appearance. Before macOS 26 and under Reduce
/// Transparency the plate is SYNTHESIZED from the terminal colors instead (`glass(over:)`): the
/// accessibility setting makes every system material opaque in the WINDOW's appearance, which over a
/// dark theme on a light system is a white slab. The spinner cycles the style's frames on a
/// `TimelineView` at the style's own interval; it animates under Reduce Motion too, since it reports
/// state rather than decorating.
struct HudNoticeView: View {
    let spec: HudSpec
    /// The terminal foreground, taken when the spec sets no `--text-color`.
    let foreground: Color
    /// The terminal background the glass is mixed from; nil reads as black.
    let background: NSColor?
    /// What a click on the plate does; nil leaves the notice inert, which is every HUD without `--reveal`.
    var onTap: (() -> Void)?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Clearance from the pane edge on the anchored sides. The top row sits a quarter of the pane down,
    /// where a sheet would, rather than on the first prompt lines; the bottom row is a toast's margin.
    static let topInsetFraction = 0.25
    static let edgeInset = EdgeInsets(top: 0, leading: 20, bottom: 28, trailing: 20)

    static func inset(paneHeight: CGFloat) -> EdgeInsets {
        var inset = edgeInset
        inset.top = paneHeight * topInsetFraction
        return inset
    }
    static let messageFont = Font.system(size: 15, weight: .semibold)
    static let detailFont = Font.system(size: 13)
    static let detailOpacity = 0.75
    static let cornerRadius: CGFloat = 14
    /// How far the plate lifts off the terminal background toward its foreground, and how much of what
    /// it covers still shows through — the two numbers that make it read as glass rather than a card.
    static let glassLift = 0.10
    static let glassOpacity = 0.9

    var body: some View {
        let plate = NSColor(agtermHex: spec.backgroundColor)
        let text = VStack(alignment: horizontalAlignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let spinner = spec.spinner { HudSpinnerGlyph(style: spinner) }
                Text(spec.message)
                    .font(Self.messageFont)
            }
            if let detail = spec.detail, !detail.isEmpty {
                Text(detail)
                    .font(Self.detailFont)
                    .opacity(Self.detailOpacity)
            }
        }
        .multilineTextAlignment(textAlignment)
        .foregroundStyle(NSColor(agtermHex: spec.textColor).map { Color(nsColor: $0) } ?? foreground)
        .fixedSize(horizontal: false, vertical: true)

        let padded = text
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if let plate {
                padded.background(Color(nsColor: plate), in: shape)
            } else if #available(macOS 26, *), !reduceTransparency {
                padded
                    .glassEffect(.regular, in: shape)
                    .colorScheme(Self.isDark(background) ? .dark : .light)
            } else {
                padded
                    .background(Color(nsColor: Self.glass(over: background)).opacity(reduceTransparency ? 1 : Self.glassOpacity),
                                in: shape)
                    .overlay(shape.strokeBorder(foreground.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            }
        }
        .modifier(HudTapModifier(shape: shape, onTap: onTap))
    }

    /// Whether `background` reads as dark; relative luminance, nil reads as dark.
    static func isDark(_ background: NSColor?) -> Bool {
        guard let c = background?.usingColorSpace(.sRGB) else { return true }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent < 0.5
    }

    /// The plate color: the terminal background nudged toward white or black, whichever is the far side
    /// of its luminance, so it lifts off a dark pane and sinks into a light one.
    static func glass(over background: NSColor?) -> NSColor {
        let base = background?.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let toward: NSColor = isDark(base) ? .white : .black
        return base.blended(withFraction: glassLift, of: toward) ?? base
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch spec.position.horizontalBand {
        case .leading: .leading
        case .middle: .center
        case .trailing: .trailing
        }
    }

    private var textAlignment: TextAlignment {
        switch spec.position.horizontalBand {
        case .leading: .leading
        case .middle: .center
        case .trailing: .trailing
        }
    }

}

/// The click a `--reveal` panel takes: the plate alone is the hit region, so the margins around it stay
/// the session's, and the pointer says it is a link. A panel with no action is left untouched, which keeps
/// the inert HUD's passivity contract exactly as it was.
private struct HudTapModifier: ViewModifier {
    let shape: RoundedRectangle
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onTap {
            content
                .contentShape(shape)
                .onTapGesture(perform: onTap)
                .onHover { inside in
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

/// One frame of the spinner at a time, in the monospaced face so every frame takes the same width and
/// the message beside it never shifts.
private struct HudSpinnerGlyph: View {
    let style: HudSpinner

    var body: some View {
        TimelineView(.periodic(from: .now, by: style.interval)) { context in
            let frames = style.frames
            let index = Int(context.date.timeIntervalSinceReferenceDate / style.interval) % frames.count
            Text(frames[index])
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
    }
}
