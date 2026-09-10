import agtermCore
import SwiftUI

/// Bridges one session's `MarkdownReaderView` into SwiftUI, `TerminalView`'s sibling for the reader slot.
/// Unlike a terminal surface the web view is owned HERE, not by the `Session`: nothing outlives the panel,
/// so `dismantleNSView` frees it and the deck keys the view on `Session.readerSlotGeneration` to rebuild
/// it for a replacement.
struct ReaderView: NSViewRepresentable {
    let path: String

    func makeNSView(context _: Context) -> MarkdownReaderView {
        MarkdownReaderView(path: path)
    }

    func updateNSView(_ view: MarkdownReaderView, context _: Context) {
        if view.path != path { view.load(path: path) }
    }

    static func dismantleNSView(_ view: MarkdownReaderView, coordinator _: ()) {
        view.teardown()
    }
}
