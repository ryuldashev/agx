import agtermCore
import XCTest
@testable import agterm

/// The reader panel's app-side seams: the geometry `OverlayPanelStyle` resolves for it, and the bundled page
/// `MarkdownReaderView` loads — both live in the app target, so this cannot be host-free.
@MainActor
final class ReaderPanelTests: XCTestCase {
    func testReaderStyleIsFramedInteractiveAndNeverABackdrop() {
        let style = OverlayPanelStyle.reader(ReaderSpec(path: "/tmp/a.md", position: .centerRight, sizePercent: 45))
        XCTAssertTrue(style.interactive, "the user scrolls and selects in the document")
        XCTAssertTrue(style.framed)
        XCTAssertFalse(style.backdrop, "a reader must not mute the session beside it")
        XCTAssertEqual(style.shadowRadius, 0)
        XCTAssertEqual(style.widthFraction, 0.45, accuracy: 0.001)
        XCTAssertEqual(style.heightFraction, CGFloat(ReaderLayout.heightPercent) / 100, accuracy: 0.001)
    }

    func testTheDefaultAnchorSitsRightAndTheHeightCentersVertically() {
        let style = OverlayPanelStyle.reader(ReaderSpec(path: "/tmp/a.md"))
        XCTAssertGreaterThan(style.horizontalOffset(paneWidth: 1000), 0)
        XCTAssertEqual(style.verticalOffset(paneHeight: 800), 0, "a near-full-height panel has no room to travel")
        XCTAssertLessThan(OverlayPanelStyle.reader(ReaderSpec(path: "/tmp/a.md", position: .centerLeft))
            .horizontalOffset(paneWidth: 1000), 0)
    }

    func testTheReaderPageIsBundled() throws {
        let dir = try XCTUnwrap(MarkdownReaderView.webDir(), "Resources/reader must ship in the app bundle")
        for file in ["index.html", "app.js", "reader.css", "markdown-it.min.js", "purify.min.js", "idiomorph.min.js"] {
            XCTAssertTrue(FileManager.default.isReadableFile(atPath: dir.appendingPathComponent(file).path), file)
        }
    }

    func testAReaderViewBuildsOverAFileAndTearsDown() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("reader-\(UUID().uuidString).md")
        try "# hello\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let view = MarkdownReaderView(path: file.path)
        XCTAssertEqual(view.path, file.path)
        XCTAssertEqual(view.subviews.count, 2, "the web view and the missing-file banner")
        view.teardown()
        XCTAssertEqual(view.subviews.count, 1, "teardown removes the web view")
    }

    func testAReaderNeverTouchesTheOverlayGates() {
        let session = Session(initialCwd: NSTemporaryDirectory())
        session.readerSpec = ReaderSpec(path: "/tmp/a.md")
        XCTAssertFalse(DeckPaneGates.coverActive(session))
        XCTAssertFalse(session.overlayActive)
    }
}
