import agtermCore
import XCTest
@testable import agterm

/// The reader's app-side seams: the bundled page `MarkdownReaderView` loads and the view it builds, both
/// of which need the app bundle and WebKit, so this cannot be host-free.
@MainActor
final class ReaderPanelTests: XCTestCase {
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
        XCTAssertEqual(view.subviews.count, 3, "the web view, the missing-file banner and the pop-out button")
        view.teardown()
        XCTAssertEqual(view.subviews.count, 2, "teardown removes the web view")
    }

    func testThePopOutButtonIsLabeledForTheStandaloneReader() throws {
        let view = MarkdownReaderView(path: "/tmp/absent-\(UUID().uuidString).md")
        defer { view.teardown() }
        let button = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        XCTAssertEqual(button.title, "Open in Reader")
        XCTAssertEqual(MarkdownReaderView.standaloneReaderBundleID, "uz.marshub.mmee.reader")
    }

    func testFontZoomStepsFromThePanePresetAndStaysBounded() {
        let view = MarkdownReaderView(path: "/tmp/absent-\(UUID().uuidString).md")
        defer { view.teardown() }
        XCTAssertEqual(MarkdownReaderView.defaultFontSize, 14, "smaller than the standalone window's 17px")
        view.adjustFontSize(by: 100)
        view.adjustFontSize(by: -200)
        view.resetFontSize()
        XCTAssertEqual(view.subviews.count, 3, "zoom never rebuilds the view tree")
    }

    func testAReaderNeverTouchesTheOverlayGates() {
        let session = Session(initialCwd: NSTemporaryDirectory())
        session.readerSpec = ReaderSpec(path: "/tmp/a.md")
        XCTAssertFalse(DeckPaneGates.coverActive(session))
        XCTAssertFalse(session.overlayActive)
    }
}
