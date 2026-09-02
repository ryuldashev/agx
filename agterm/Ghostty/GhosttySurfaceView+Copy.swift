import agtermCore
import AppKit
import GhosttyKit

extension GhosttySurfaceView {
    /// The physical `C` key (ANSI keycode), matched by POSITION so ⌘C still copies on a layout whose C key
    /// produces `с` — the same reason `ghostty-defaults.conf` binds `super+key_c` as the fallback layer.
    static let copyKeyCode: UInt16 = 8

    /// Copy this pane's selection through `CopyCleanup` and flash the pane. Returns false when there is
    /// nothing selected, so a caller can fall back to libghostty's own `copy_to_clipboard`.
    @discardableResult
    func copySelectionCleaned() -> Bool {
        guard let text = readSelection(), !text.isEmpty else { return false }
        let cleaned = GhosttyApp.shared.copyCleanupEnabled ? CopyCleanup.clean(text) : text
        guard !cleaned.isEmpty else { return false }
        GhosttyCallbacks.setClipboard(cleaned)
        flashCopied()
        return true
    }

    /// Follow a mouse-up that left a selection: libghostty's own copy-on-select has already put the RAW
    /// text on the pasteboard by now, so this replaces it with the cleaned form and flashes. Skipped
    /// entirely when neither is enabled, leaving ghostty's behavior untouched.
    func copyOnSelectFollowUp() {
        guard GhosttyApp.shared.copyCleanupEnabled || GhosttyApp.shared.copyFlashEnabled else { return }
        copySelectionCleaned()
    }

    /// A brief "Copied" pill at the pointer (the pane's bottom-right corner when no mouse point is known
    /// yet, e.g. a ⌘C right after a keyboard select-all). Layer-backed and non-interactive: it never enters
    /// the responder chain, so a flash cannot take focus off the terminal.
    func flashCopied() {
        guard GhosttyApp.shared.copyFlashEnabled else { return }
        (copyFlashView as? CopyFlashView)?.cancel()
        let pill = CopyFlashView(text: NSLocalizedString("Copied", comment: "copy confirmation flash"))
        pill.frame.origin = flashOrigin(for: pill.frame.size)
        addSubview(pill)
        copyFlashView = pill
        pill.play { [weak self, weak pill] in
            guard let pill, self?.copyFlashView === pill else { return }
            self?.copyFlashView = nil
        }
    }

    /// Anchor the pill just above-right of the pointer, clamped inside the pane so a selection ending at an
    /// edge still shows it whole. `lastReportedMousePoint` is in libghostty's top-left space, hence the flip
    /// back into this (unflipped) view's coordinates; its `(-1, -1)` "pointer left" sentinel clamps to the
    /// corner like any other out-of-bounds point.
    private func flashOrigin(for size: CGSize) -> CGPoint {
        let inset: CGFloat = 8
        let maxX = max(inset, bounds.maxX - size.width - inset)
        let maxY = max(inset, bounds.maxY - size.height - inset)
        guard let point = lastReportedMousePoint else { return CGPoint(x: maxX, y: inset) }
        return CGPoint(x: min(max(point.x + inset, inset), maxX),
                       y: min(max(bounds.height - point.y + inset, inset), maxY))
    }
}

/// The "Copied" pill: a rounded label that fades in fast, holds, then fades out — sub-second so it reads as
/// confirmation, never as a dialog. `hitTest` returns nil so clicks fall through to the terminal beneath.
final class CopyFlashView: NSView {
    private static let fadeIn: TimeInterval = 0.09
    private static let hold: TimeInterval = 0.7
    private static let fadeOut: TimeInterval = 0.22

    private var onFinished: (() -> Void)?

    init(text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = GhosttyApp.shared.terminalBackgroundColor ?? .black
        label.sizeToFit()
        super.init(frame: NSRect(x: 0, y: 0, width: label.frame.width + 18, height: label.frame.height + 8))
        label.frame.origin = CGPoint(x: 9, y: 4)
        wantsLayer = true
        layer?.backgroundColor = (GhosttyApp.shared.terminalForegroundColor ?? .white).withAlphaComponent(0.9).cgColor
        layer?.cornerRadius = frame.height / 2
        alphaValue = 0
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Never take a click: the pill sits over live terminal content and must not swallow a drag that starts
    /// under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func play(completion: @escaping () -> Void) {
        onFinished = completion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeIn
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            animator().alphaValue = 1
        }
        // a delayed perform, not `asyncAfter`: the hold stays on the main run loop and is cancellable, so a
        // pill replaced mid-hold takes its pending fade-out with it.
        perform(#selector(fadeOut), with: nil, afterDelay: Self.fadeIn + Self.hold)
    }

    /// Drop the pill immediately (a second copy landed): cancels the pending fade so the outgoing view's
    /// timer can't fire against the new one.
    func cancel() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        onFinished = nil
        removeFromSuperview()
    }

    @objc private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOut
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            removeFromSuperview()
            onFinished?()
            onFinished = nil
        }
    }
}
