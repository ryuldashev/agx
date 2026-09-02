import Testing
@testable import agtermCore

@Suite struct CopyCleanupTests {
    @Test func stripsAFrameGutterSharedByEveryLine() {
        let copied = "│ func main() {\n│     print(\"hi\")\n│ }"
        #expect(CopyCleanup.clean(copied) == "func main() {\n    print(\"hi\")\n}")
    }

    @Test func keepsAGutterCharacterThatIsContent() {
        // one line without the marker means the run is text, not a frame
        let copied = "│ shell pipe\nls | wc -l"
        #expect(CopyCleanup.clean(copied) == copied)
    }

    @Test func dropsTrailingPaddingAndSurroundingBlankLines() {
        #expect(CopyCleanup.clean("\n\ncode   \nmore\t\n\n") == "code\nmore")
    }

    @Test func deindentsByTheSharedIndentOnly() {
        #expect(CopyCleanup.clean("    a\n      b") == "a\n  b")
        #expect(CopyCleanup.clean("a\n  b") == "a\n  b")
    }

    @Test func leavesOrdinaryShellOutputByteIdentical() {
        let plain = "total 8\ndrwxr-xr-x  3 rus  staff   96 Sep  3 00:51 ."
        #expect(CopyCleanup.clean(plain) == plain)
        #expect(CopyCleanup.clean("") == "")
        #expect(CopyCleanup.clean("\n\n") == "")
    }

    @Test func keepsBlankLinesInsideTheBlock() {
        #expect(CopyCleanup.clean("│ a\n│\n│ b") == "a\n\nb")
    }
}

@Suite struct LinkFileReferenceTests {
    @Test func splitsAPathFromItsLineAndColumn() {
        let swiftFile = LinkPolicy.fileReference(in: "src/main.swift:120")
        #expect(swiftFile?.path == "src/main.swift")
        #expect(swiftFile?.line == 120)
        let log = LinkPolicy.fileReference(in: "/tmp/x.log:9:4")
        #expect(log?.path == "/tmp/x.log")
        #expect(log?.line == 9)
        let plain = LinkPolicy.fileReference(in: "./a.txt")
        #expect(plain?.path == "./a.txt")
        #expect(plain?.line == nil)
    }

    @Test func refusesUrlsAndDegenerateInput() {
        #expect(LinkPolicy.fileReference(in: "https://example.com") == nil)
        #expect(LinkPolicy.fileReference(in: "mailto:a@b.c") == nil)
        #expect(LinkPolicy.fileReference(in: ":120") == nil)
        #expect(LinkPolicy.fileReference(in: "   ") == nil)
    }

    @Test func keepsANonNumericTail() {
        let colonName = LinkPolicy.fileReference(in: "/tmp/foo:bar")
        #expect(colonName?.path == "/tmp/foo:bar")
        #expect(colonName?.line == nil)
    }
}
