import agtermCore
import SwiftUI

import AppKit

/// Bridges one session's `MarkdownReaderView` into SwiftUI, `TerminalView`'s sibling for the split pane.
/// Unlike a terminal surface the web view is owned HERE, not by the `Session`: nothing outlives the pane,
/// so `dismantleNSView` frees it and the deck keys the view on `Session.readerSlotGeneration` to rebuild
/// it for a replacement. `background` is the terminal's, so the page is tinted to the pane beside it.
struct ReaderView: NSViewRepresentable {
    let path: String
    let background: NSColor?
    /// The pane's "Open in Reader" button handed the file to the standalone app; the owner closes the reader.
    let onPopOut: () -> Void
    /// The document took first responder: the owner marks the right pane focused, as a shell click would.
    let onFocus: () -> Void
    /// A `.md` link in the document was clicked: the owner shows that file here.
    let onOpenMarkdown: (String) -> Void

    func makeNSView(context _: Context) -> MarkdownReaderView {
        let view = MarkdownReaderView(path: path)
        view.apply(background: background)
        view.onPopOut = onPopOut
        view.onFocusChange = { focused in if focused { onFocus() } }
        view.onOpenMarkdown = onOpenMarkdown
        return view
    }

    func updateNSView(_ view: MarkdownReaderView, context _: Context) {
        if view.path != path { view.load(path: path) }
        view.apply(background: background)
        view.onPopOut = onPopOut
        view.onFocusChange = { focused in if focused { onFocus() } }
        view.onOpenMarkdown = onOpenMarkdown
    }

    static func dismantleNSView(_ view: MarkdownReaderView, coordinator _: ()) {
        view.teardown()
    }
}
