import Foundation
import Testing
@testable import agtermCore

struct HudTests {
    @Test func shortMessageBoxIsContentPlusPadding() {
        let box = HudLayout.box(for: HudSpec(message: "gathering options"))

        #expect(box.columns == 17 + HudLayout.horizontalPadding * 2)
        #expect(box.rows == 1 + HudLayout.verticalPadding * 2)
    }

    @Test func emptyMessageStillProducesAOneRowBox() {
        let box = HudLayout.box(for: HudSpec(message: ""))

        #expect(box.columns == 1 + HudLayout.horizontalPadding * 2)
        #expect(box.rows == 1 + HudLayout.verticalPadding * 2)
    }

    @Test func longSingleWordIsBrokenAtMaxColumns() {
        let word = String(repeating: "x", count: 130)

        let lines = HudLayout.wrap(word, columns: HudLayout.maxColumns)
        let box = HudLayout.box(for: HudSpec(message: word))

        #expect(lines == [String(repeating: "x", count: 60), String(repeating: "x", count: 60),
                          String(repeating: "x", count: 10)])
        #expect(box.columns == HudLayout.maxColumns + HudLayout.horizontalPadding * 2)
        #expect(box.rows == 3 + HudLayout.verticalPadding * 2)
    }

    @Test func wordWrapKeepsWordsWholeUpToMaxColumns() {
        let message = Array(repeating: "word", count: 20).joined(separator: " ")

        let lines = HudLayout.wrap(message, columns: HudLayout.maxColumns)

        #expect(lines.count == 2)
        #expect(lines[0] == Array(repeating: "word", count: 12).joined(separator: " "))
        #expect(lines[1] == Array(repeating: "word", count: 8).joined(separator: " "))
        #expect(lines.allSatisfy { $0.count <= HudLayout.maxColumns })
    }

    @Test func detailFollowsMessageAfterASingleEmptyLine() {
        let spec = HudSpec(message: "gathering options", detail: "scanning 4 repositories")

        let box = HudLayout.box(for: spec)

        #expect(HudLayout.bodyLines(for: spec) == ["gathering options", "", "scanning 4 repositories"])
        #expect(box.columns == 23 + HudLayout.horizontalPadding * 2)
        #expect(box.rows == 3 + HudLayout.verticalPadding * 2)
    }

    @Test func emptyDetailAddsNoSeparator() {
        let spec = HudSpec(message: "working", detail: "   ")

        #expect(HudLayout.bodyLines(for: spec) == ["working"])
    }

    // `HudLayout.spinnerWidth` reserves exactly two cells, so a frame carrying a space or a double-width
    // glyph would shift the message beside it.
    @Test(arguments: HudSpinner.allCases) func everyFrameIsOneSpacelessScalar(style: HudSpinner) {
        #expect(!style.frames.isEmpty)
        for frame in style.frames {
            #expect(HudLayout.cellCount(frame) == 1, "\(style.rawValue) frame \(frame.debugDescription)")
            #expect(!frame.contains(" "), "\(style.rawValue) frame \(frame.debugDescription) would split")
        }
        #expect(style.interval > 0)
    }

    @Test func embeddedNewlinesBecomeHardBreaksWithNoBlankLines() {
        let spec = HudSpec(message: "one\n\ntwo three", detail: "four\nfive")

        #expect(HudLayout.bodyLines(for: spec) == ["one", "two three", "", "four", "five"])
        #expect(HudLayout.box(for: spec).rows == 5 + HudLayout.verticalPadding * 2)
    }

    @Test func spinnerWidensTheBoxWithoutRewrapping() {
        let plain = HudLayout.box(for: HudSpec(message: "hi"))
        let spinning = HudLayout.box(for: HudSpec(message: "hi", spinner: .braille))

        #expect(spinning.columns == plain.columns + HudLayout.spinnerWidth)
        #expect(spinning.rows == plain.rows)
    }

    @Test func eachAxisMeasuresItsOwnNeed() {
        let pane = PaneMetrics(cellWidth: 8, cellHeight: 18, paneWidth: 1200, paneHeight: 800)

        // 22 cells = 176pt of 1200 = 15%, 3 rows = 54pt of 800 = 7%
        #expect(HudLayout.widthPercent(box: (columns: 22, rows: 3), pane: pane) == 15)
        #expect(HudLayout.heightPercent(box: (columns: 22, rows: 3), pane: pane) == 7)
        // 20 rows = 360pt of 800 = 45%, and the width is unmoved by it
        #expect(HudLayout.widthPercent(box: (columns: 22, rows: 20), pane: pane) == 15)
        #expect(HudLayout.heightPercent(box: (columns: 22, rows: 20), pane: pane) == 45)
    }

    // pins the square panel: one percent used to be the larger of the two needs, so a message wide enough
    // to want 71% of the pane took 71% of its HEIGHT too and left three lines of text in a vast empty box.
    @Test func aWideMessageDoesNotMakeATallPanel() {
        let pane = PaneMetrics(cellWidth: 8, cellHeight: 18, paneWidth: 700, paneHeight: 800)
        let spec = HudSpec(message: "waiting on the package index — this can take a minute on a cold cache",
                           detail: "registry.example.org")
        let box = HudLayout.box(for: spec)

        #expect(HudLayout.widthPercent(box: box, pane: pane) == 71)
        #expect(HudLayout.heightPercent(box: box, pane: pane) == 14)
    }

    @Test func aCallerOverrideIsBoundedByTheSameClampTheMeasurementTakes() {
        #expect(HudLayout.clampSizePercent(100) == HudLayout.maxSizePercent)
        #expect(HudLayout.clampSizePercent(1) == HudLayout.minSizePercent)
        #expect(HudLayout.clampSizePercent(40) == 40)
        #expect(HudLayout.clampSizePercent(HudLayout.maxSizePercent) == HudLayout.maxSizePercent)
    }

    // the floor is a WIDTH rule — a panel narrower than this reads as a sliver — and applying it to the
    // height is what made a one-line message occupy a tenth of the pane.
    @Test func onlyTheWidthTakesTheMinimumFloor() {
        let pane = PaneMetrics(cellWidth: 8, cellHeight: 18, paneWidth: 2000, paneHeight: 1000)

        #expect(HudLayout.widthPercent(box: (columns: 6, rows: 3), pane: pane) == HudLayout.minSizePercent)
        #expect(HudLayout.heightPercent(box: (columns: 6, rows: 3), pane: pane) == 6)
    }

    @Test func aHugeMessageGrowsTallAndIsCappedThere() {
        let pane = PaneMetrics(cellWidth: 8, cellHeight: 18, paneWidth: 1200, paneHeight: 800)
        let spec = HudSpec(message: Array(repeating: "word", count: 600).joined(separator: " "))
        let box = HudLayout.box(for: spec)

        // it wraps at maxColumns, so the width settles well inside the cap while the rows run past it
        #expect(HudLayout.widthPercent(box: box, pane: pane) == 42)
        #expect(HudLayout.heightPercent(box: box, pane: pane) == HudLayout.maxSizePercent)
    }

    @Test func unmeasuredPaneWidensButDoesNotHeighten() {
        let pane = PaneMetrics(cellWidth: 8, cellHeight: 18, paneWidth: 0, paneHeight: 0)

        #expect(HudLayout.widthPercent(box: (columns: 10, rows: 3), pane: pane) == HudLayout.maxSizePercent)
        #expect(HudLayout.heightPercent(box: (columns: 10, rows: 3), pane: pane) == HudLayout.minSizePercent)
    }

    // `String.count` counts grapheme clusters, which disagree with scalars on every combining mark. macOS
    // hands text back decomposed, so it is precomposed first and what is left measures the same everywhere.
    @Test func widthIsCountedInScalars() {
        let decomposed = "cafe\u{0301} au lait"

        let lines = HudLayout.bodyLines(for: HudSpec(message: decomposed))

        #expect(lines.count == 1)
        #expect(lines[0].unicodeScalars.count == 12, "the line must be precomposed, not NFD")
        #expect(HudLayout.cellCount(lines[0]) == 12)
        #expect(HudLayout.box(for: HudSpec(message: decomposed)).columns
            == 12 + HudLayout.horizontalPadding * 2)
    }

    // a ZWJ sequence is ONE Character and FIVE code points; the box counts the latter, even though it
    // renders as two display columns.
    @Test func aZwjSequenceIsMeasuredInCodePointsNotClusters() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}"

        #expect(family.count == 1)
        #expect(HudLayout.cellCount(family) == 5)
        #expect(HudLayout.box(for: HudSpec(message: family)).columns == 5 + HudLayout.horizontalPadding * 2)
    }

    @Test func omittedPositionAndSpinnerDecodeToTheirDefaults() throws {
        let json = Data(#"{"message":"working"}"#.utf8)

        let spec = try JSONDecoder().decode(HudSpec.self, from: json)

        #expect(spec.message == "working")
        #expect(spec.position == .center)
        #expect(spec.spinner == nil)
        #expect(spec.detail == nil)
        #expect(spec.backgroundColor == nil)
        #expect(spec.sizePercent == nil)
    }

    @Test(arguments: HudPosition.allCases) func everyPositionRoundTrips(position: HudPosition) throws {
        let spec = HudSpec(message: "working", detail: "soon", spinner: .braille,
                           backgroundColor: "#112233", sizePercent: 40, position: position)

        let decoded = try JSONDecoder().decode(HudSpec.self, from: JSONEncoder().encode(spec))

        #expect(decoded == spec)
        #expect(decoded.position == position)
    }

    @Test func positionNamesDeriveFromTheCases() {
        #expect(HudPosition.validNamesList
            == "top-left|top-center|top-right|center-left|center|center-right"
            + "|bottom-left|bottom-center|bottom-right")
        #expect(HudPosition.validNamesPhrase
            == "top-left, top-center, top-right, center-left, center, center-right, "
            + "bottom-left, bottom-center, bottom-right")
    }

    @Test func acceptedNamesAddTheAliasesToTheCanonicalSet() {
        #expect(HudPosition.acceptedNamesList == HudPosition.validNamesList + "|top|bottom")
        #expect(HudPosition.acceptedNamesPhrase == HudPosition.validNamesPhrase + ", top, bottom")
    }

    @Test func hudPositionSpellingMatchesTheWatermarkAnchors() {
        #expect(Set(HudPosition.allCases.map(\.rawValue))
            == Set(BackgroundWatermark.Position.allCases.map(\.rawValue)))
    }

    @Test(arguments: [("top", HudPosition.topCenter), ("bottom", .bottomCenter)])
    func bareAliasesNormalizeToTheMiddleColumn(raw: String, expected: HudPosition) {
        #expect(HudPosition.parse(raw) == expected)
        #expect(expected.rawValue != raw)
    }

    @Test func aliasesSurviveDecodingAndReEncodeCanonically() throws {
        let decoded = try JSONDecoder().decode(HudPosition.self, from: Data(#""top""#.utf8))

        #expect(decoded == .topCenter)
        #expect(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self) == #""top-center""#)
    }

    @Test(arguments: ["middle", "top-middle", "TOP", "", "left"])
    func parseRejectsEverythingOutsideTheAcceptedSet(raw: String) {
        #expect(HudPosition.parse(raw) == nil)
    }

    @Test func everyAnchorRoundTripsThroughItsRawValue() {
        for position in HudPosition.allCases {
            #expect(HudPosition.parse(position.rawValue) == position)
        }
    }

    @Test func bandsSplitTheAnchorsIntoThreeRowsAndThreeColumns() {
        #expect(HudPosition.allCases.filter { $0.verticalBand == .leading }
            == [.topLeft, .topCenter, .topRight])
        #expect(HudPosition.allCases.filter { $0.horizontalBand == .trailing }
            == [.topRight, .centerRight, .bottomRight])
        #expect(HudPosition.center.verticalBand == .middle)
        #expect(HudPosition.center.horizontalBand == .middle)
    }

    /// The margin has to fit on the WIDTH too now that anchors travel horizontally, and the width is the
    /// axis a caller can override, so `clampSizePercent` is what has to hold the bound.
    @Test func edgeMarginLeavesRoomForTheLargestPanelOnBothAxes() {
        #expect(HudPosition.edgeMarginPercent * 2 + HudLayout.maxSizePercent <= 100)
        #expect(HudPosition.edgeMarginPercent * 2 + HudLayout.clampSizePercent(100) <= 100)
    }
}
