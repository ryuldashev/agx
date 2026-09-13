import agtermCore
import AppKit
import SwiftUI

/// The passive `session.hud.*` panel, drawn natively over the session: a message in the system face at the
/// weight of a macOS notice, its detail a size down and dimmed, and NO plate unless the caller set
/// `--background-color`. Legibility over a wallpaper or a terminal of either polarity comes from a two-layer
/// text shadow in the terminal background's own polarity, so the text never needs a box to sit on. The
/// spinner cycles the style's frames on a `TimelineView` at the style's own interval; it animates under
/// Reduce Motion too, since it reports state rather than decorating.
struct HudNoticeView: View {
    let spec: HudSpec
    /// The terminal foreground, taken when the spec sets no `--text-color`.
    let foreground: Color
    /// Whether the text sits over a dark ground; picks the shadow's polarity when there is no plate.
    let overDark: Bool

    /// Clearance from the pane edge on the anchored sides.
    static let edgeInset: CGFloat = 12
    static let messageFont = Font.system(size: 13, weight: .semibold)
    static let detailFont = Font.system(size: 11)
    static let detailOpacity = 0.75
    static let plateCornerRadius: CGFloat = 8

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

        if let plate {
            text
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: plate), in: RoundedRectangle(cornerRadius: Self.plateCornerRadius))
        } else {
            let shadow = overDark ? Color.black : Color.white
            text
                .shadow(color: shadow.opacity(0.7), radius: 1.5, y: 1)
                .shadow(color: shadow.opacity(0.4), radius: 8)
        }
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

    /// Whether `background` reads as dark, for the shadow polarity. Relative luminance, sRGB, no gamma
    /// correction — a threshold, not a measurement.
    static func isDark(_ background: NSColor?) -> Bool {
        guard let c = background?.usingColorSpace(.sRGB) else { return true }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent < 0.5
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }
}
