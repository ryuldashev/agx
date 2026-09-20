import AppKit

/// Places an NSAlert accessory view under the alert's TEXT column.
///
/// AppKit parks an accessory narrower than the alert at the window's left margin — the icon column — so
/// without this every option row hangs left of every line of text. Extracted from the first-run alert when the
/// permissions primer needed the same alignment; the measurement is the interesting part and there is no
/// second way to do it.
@MainActor
enum AlertAccessoryLayout {
    /// Indent `stack` inside `container` to line up with the alert's message text. Measured after
    /// `layout()`, because the text column's x is not knowable before it, then corrected against
    /// `reference`: a stack positions its views by alignment rect, and a checkbox's differs from a text
    /// field's by a couple of points.
    static func indent(_ stack: NSStackView, container: NSView, reference: NSView, in alert: NSAlert) {
        guard let content = alert.window.contentView,
              let text = messageLabel(in: content, matching: alert.messageText) else { return }
        let textX = leadingX(of: text, in: content)
        let offset = textX - leadingX(of: container, in: content)
        guard offset > 0 else { return }
        stack.setFrameOrigin(NSPoint(x: offset, y: stack.frame.origin.y))
        container.setFrameSize(NSSize(width: offset + stack.frame.width, height: container.frame.height))
        alert.layout()
        let residual = leadingX(of: reference, in: content) - textX
        guard abs(residual) > 0.5 else { return }
        stack.setFrameOrigin(NSPoint(x: stack.frame.origin.x - residual, y: stack.frame.origin.y))
        alert.layout()
    }

    /// A view's visible left edge in `content` coordinates: the frame inset by the alignment rect, which is
    /// what AppKit lines controls up by and what the eye reads as the edge.
    private static func leadingX(of view: NSView, in content: NSView) -> CGFloat {
        view.convert(NSPoint.zero, to: content).x + view.alignmentRectInsets.left
    }

    /// The alert's title label, the leftmost element of its text column.
    private static func messageLabel(in view: NSView, matching title: String) -> NSView? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.stringValue == title { return field }
            if let found = messageLabel(in: subview, matching: title) { return found }
        }
        return nil
    }
}
