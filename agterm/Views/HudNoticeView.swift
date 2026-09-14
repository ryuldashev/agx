import agtermCore
import AppKit
import SwiftUI

/// The passive `session.hud.*` panel, drawn natively over the session: a message in the system face at the
/// weight of a macOS notice, its detail a size down and dimmed, on Liquid Glass (a material before
/// macOS 26, an opaque window color under Reduce Transparency) — or on a solid plate when the caller set
/// `--background-color`. The spinner cycles the style's frames on a `TimelineView` at the style's own
/// interval; it animates under Reduce Motion too, since it reports state rather than decorating.
struct HudNoticeView: View {
    let spec: HudSpec
    /// The terminal foreground, taken when the spec sets no `--text-color`.
    let foreground: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Clearance from the pane edge on the anchored sides: enough that a top notice clears the first
    /// prompt lines rather than sitting on them.
    static let edgeInset = EdgeInsets(top: 40, leading: 20, bottom: 28, trailing: 20)
    static let messageFont = Font.system(size: 15, weight: .semibold)
    static let detailFont = Font.system(size: 13)
    static let detailOpacity = 0.75
    static let cornerRadius: CGFloat = 14

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
        if let plate {
            padded.background(Color(nsColor: plate), in: shape)
        } else if reduceTransparency {
            padded.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else if #available(macOS 26, *) {
            padded.glassEffect(.regular, in: shape)
        } else {
            padded
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
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
