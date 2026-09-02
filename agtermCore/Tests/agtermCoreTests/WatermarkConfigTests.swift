import Foundation
import Testing
@testable import agtermCore

struct WatermarkConfigTests {
    @Test func imageOverlayEmitsAllKeys() {
        let watermark = BackgroundWatermark(kind: .image, imagePath: "/tmp/bg.png", opacity: 0.2,
                                            fit: .cover, position: .topLeft, repeats: true)
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: "/tmp/bg.png", fontSize: nil)
        #expect(text.contains("background-opacity = 1\n"))
        #expect(text.contains("background-image = /tmp/bg.png\n"))
        #expect(text.contains("background-image-opacity = 0.2\n"))
        #expect(text.contains("background-image-fit = cover\n"))
        #expect(text.contains("background-image-position = top-left\n"))
        #expect(text.contains("background-image-repeat = true\n"))
        #expect(!text.contains("font-size"))
    }

    @Test func overlayDefaultsFitAndPositionWhenNil() {
        let watermark = BackgroundWatermark(kind: .text, text: "DRAFT")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: "/x/draft.png", fontSize: nil)
        #expect(text.contains("background-image-fit = contain\n"))
        #expect(text.contains("background-image-position = center\n"))
        #expect(text.contains("background-image-repeat = false\n"))
        // unset means no line at all — ghostty's own 1.0 default applies.
        #expect(!text.contains("background-image-opacity"))
    }

    @Test func overlayPreservesFontZoomAlongsideImage() {
        let watermark = BackgroundWatermark(kind: .image, imagePath: "/a.png")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: "/a.png", fontSize: 16)
        #expect(text.contains("background-image = /a.png\n"))
        #expect(text.contains("font-size = 16\n"))
    }

    @Test func clearWithZoomEmitsOnlyFontSize() {
        let text = WatermarkConfig.overlayText(watermark: nil, resolvedImagePath: nil, fontSize: 13.5)
        #expect(text == "font-size = 13.5\n")
    }

    @Test func clearWithoutZoomIsEmpty() {
        #expect(WatermarkConfig.overlayText(watermark: nil, resolvedImagePath: nil, fontSize: nil) == "")
    }

    @Test func missingResolvedPathDropsImageKeysButKeepsZoom() {
        // a nil resolved path is a `.text` watermark whose PNG failed to render.
        let watermark = BackgroundWatermark(kind: .text, text: "x")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: nil, fontSize: 14)
        #expect(!text.contains("background-image"))
        #expect(text == "font-size = 14\n")
    }

    @Test func overlayDropsImageForControlCharPath() {
        // defense-in-depth on the restore path: a control char in the path is only reachable by hand-editing
        // workspaces.json, and fit/position are enums, so the path is the one free-text field to guard.
        let poisoned = "/tmp/x.png\nclipboard-read = allow"
        let watermark = BackgroundWatermark(kind: .image, imagePath: poisoned)
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: poisoned, fontSize: 14)
        #expect(!text.contains("background-image"))
        #expect(!text.contains("clipboard-read"))
        #expect(text == "font-size = 14\n")
    }

    @Test func colorOverlayEmitsBackgroundAtWindowOpacity() {
        let watermark = BackgroundWatermark(kind: .color, colorHex: "#ff0000")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: nil, fontSize: nil)
        #expect(text.contains("background = #ff0000\n"))
        #expect(text.contains("background-opacity = 1\n"))   // the default windowOpacity is solid
        #expect(!text.contains("background-image"))
    }

    @Test func colorOverlayHonorsWindowTranslucency() {
        // a solid color is drawn at the Settings window translucency, not a per-call opacity, so the window
        // blur shows through.
        let watermark = BackgroundWatermark(kind: .color, colorHex: "#00ff88")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: nil, fontSize: 15, windowOpacity: 0.8)
        #expect(text.contains("background = #00ff88\n"))
        #expect(text.contains("background-opacity = 0.8\n"))
        #expect(text.contains("font-size = 15\n"))
    }

    @Test func colorOverlayClampsWindowOpacity() {
        // windowOpacity traces back to a persisted, hand-editable AppSettings value, so nan/inf and
        // out-of-range values reach this call.
        let watermark = BackgroundWatermark(kind: .color, colorHex: "#ff0000")
        func overlay(_ windowOpacity: Double) -> String {
            WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: nil, fontSize: nil, windowOpacity: windowOpacity)
        }
        #expect(overlay(1.5).contains("background-opacity = 1\n"))
        #expect(overlay(-0.2).contains("background-opacity = 0\n"))
        #expect(overlay(.nan).contains("background-opacity = 1\n"))
        #expect(overlay(.infinity).contains("background-opacity = 1\n"))
    }

    @Test func colorOverlayDropsMalformedHex() {
        // a malformed persisted hex is only reachable by hand-editing workspaces.json.
        let watermark = BackgroundWatermark(kind: .color, colorHex: "not-a-color")
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: nil, fontSize: 14)
        #expect(!text.contains("background ="))
        #expect(text == "font-size = 14\n")
    }

    @Test func formattedDropsTrailingZeroForIntegralValues() {
        #expect(WatermarkConfig.formatted(14) == "14")
        #expect(WatermarkConfig.formatted(14.0) == "14")
        #expect(WatermarkConfig.formatted(0.15) == "0.15")
        #expect(WatermarkConfig.formatted(13.5) == "13.5")
    }

    @Test func formattedAvoidsScientificNotation() {
        // String(Double) would render these as 1e-05 / 1e-06, which ghostty's config parser rejects.
        #expect(WatermarkConfig.formatted(0.00001) == "0.00001")
        #expect(!WatermarkConfig.formatted(0.000001).contains("e"))
        #expect(WatermarkConfig.formatted(0.2) == "0.2")
    }

    @Test func formattedStaysTotalForNonFiniteAndHugeValues() {
        // `Int(value)` traps on these; `formatted` must not crash even on a corrupt-snapshot fontSize.
        #expect(WatermarkConfig.formatted(.infinity) == "inf") // ghostty rejects it, but no trap
        #expect(WatermarkConfig.formatted(.nan).isEmpty == false)
        #expect(!WatermarkConfig.formatted(1e20).isEmpty)
    }

    @Test func enumValidationMatchesGhostty() {
        #expect(WatermarkConfig.isValidFit("contain"))
        #expect(WatermarkConfig.isValidFit("cover"))
        #expect(WatermarkConfig.isValidFit("stretch"))
        #expect(WatermarkConfig.isValidFit("none"))
        #expect(!WatermarkConfig.isValidFit("fill"))
        #expect(WatermarkConfig.isValidPosition("center"))
        #expect(WatermarkConfig.isValidPosition("bottom-right"))
        #expect(!WatermarkConfig.isValidPosition("middle"))
        #expect(!WatermarkConfig.isValidPosition("center-center"))
    }

    @Test func watermarkSurvivesSnapshotRoundTrip() throws {
        let watermark = BackgroundWatermark(kind: .text, text: "STAGING", colorHex: "#ffaa00", opacity: 0.18,
                                            fit: .contain, position: .center)
        let snapshot = SessionSnapshot(id: UUID(), customName: "s", cwd: "/tmp", backgroundWatermark: watermark)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.backgroundWatermark == watermark)
    }

    @Test func legacySnapshotWithoutWatermarkDecodes() throws {
        let raw = #"{"id":"\#(UUID().uuidString)","cwd":"/tmp"}"#
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(raw.utf8))
        #expect(decoded.backgroundWatermark == nil)
    }

    @Test(arguments: [
        #"{"kind":"text","text":"X","fit":"bogus"}"#,
        #"{"kind":"text","text":"X","position":"middle"}"#,
        #"{"kind":"hologram","text":"X"}"#,
    ])
    func invalidWatermarkDecodesLossilyWithoutWipingTheSession(_ badWatermark: String) throws {
        // a DataCorrupted throw would fail the whole SessionSnapshot, making PersistenceStore.load start
        // fresh and wipe every workspace/session.
        let id = UUID()
        let raw = #"{"id":"\#(id.uuidString)","cwd":"/tmp","customName":"keep","backgroundWatermark":\#(badWatermark)}"#
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: Data(raw.utf8))
        #expect(decoded.id == id)
        #expect(decoded.cwd == "/tmp")
        #expect(decoded.customName == "keep")
        #expect(decoded.backgroundWatermark == nil)
    }

    @Test(arguments: [0.0, 0.15, 0.5, 1.0])
    func opacityInRangeIsValid(_ opacity: Double) {
        #expect(WatermarkConfig.isValidOpacity(opacity))
    }

    @Test(arguments: [-0.1, 1.0001, 2.0, -100.0, Double.infinity, -Double.infinity, Double.nan])
    func opacityOutOfRangeOrNonFiniteIsInvalid(_ opacity: Double) {
        #expect(!WatermarkConfig.isValidOpacity(opacity))
    }

    @Test(arguments: ["#ff0000", "ff0000", "#FFAA00", "abcdef", "#012345"])
    func validColorHexAccepted(_ hex: String) {
        #expect(WatermarkConfig.isValidColorHex(hex))
    }

    // the last two are fullwidth Unicode hex forms: `Character.isHexDigit` accepts them but
    // `NSColor(agtermHex:)`'s `UInt32(radix:)` cannot parse them, so validation must reject them (ASCII-only).
    @Test(arguments: ["#fff", "fff", "#zzzzzz", "red", "#ff00", "#ff0000ff", "", "#", "#ＦＦ００００", "ＦＦ００００"])
    func malformedColorHexRejected(_ hex: String) {
        #expect(!WatermarkConfig.isValidColorHex(hex))
    }

    @Test(arguments: ["/tmp/bg.png", "/Users/me/My Pictures/x.png", "relative/path.png", "/tmp/日本語.png", ""])
    func imagePathWithoutControlCharsAccepted(_ path: String) {
        // the path rides a raw whole-line-remainder config value, so spaces and unicode are fine; emptiness
        // is a separate boundary check, so "" passes this gate.
        #expect(WatermarkConfig.isValidImagePath(path))
    }

    @Test(arguments: ["x.png\nclipboard-read = allow\ny.png", "a.png\r", "a\tb.png", "a.png\u{0}", "\u{1b}[2J"])
    func imagePathWithControlCharsRejected(_ path: String) {
        // the injection vector: a newline (or any scalar < 0x20) would split `background-image = <path>`
        // and let the tail inject an arbitrary ghostty key into the per-surface overlay.
        #expect(!WatermarkConfig.isValidImagePath(path))
    }

    @Test func textValidationEnforcesNonEmptyAndMaxLength() {
        #expect(WatermarkConfig.maxTextLength == 256)
        #expect(WatermarkConfig.isValidText("X"))
        #expect(WatermarkConfig.isValidText(String(repeating: "a", count: WatermarkConfig.maxTextLength)))
        #expect(!WatermarkConfig.isValidText(""))
        #expect(!WatermarkConfig.isValidText(String(repeating: "a", count: WatermarkConfig.maxTextLength + 1)))
    }

    @Test func oscOverlayNeverWritesTheBackgroundKey() {
        let text = WatermarkConfig.oscBackgroundOverlayText(fontSize: nil, windowOpacity: 0.8)
        #expect(text == "background-opacity = 0.8\n")
        // the crux of issue #309: a `background = <hex>` line here reaches ghostty's `Termio.changeConfig`,
        // which seeds the terminal's DEFAULT color layer from it. OSC 111 resets the override TO that
        // default, so writing the OSC color here makes the reset restore the OSC color, not the theme.
        #expect(!text.contains("background ="))
    }

    @Test func oscOverlayPreservesFontZoom() {
        let text = WatermarkConfig.oscBackgroundOverlayText(fontSize: 16, windowOpacity: 1)
        #expect(text.contains("background-opacity = 1\n"))
        #expect(text.contains("font-size = 16\n"))
        #expect(!text.contains("background ="))
    }

    @Test(arguments: [(2.0, "1"), (-1.0, "0"), (Double.nan, "1")])
    func oscOverlayClampsOpacity(_ opacity: Double, _ expected: String) {
        let text = WatermarkConfig.oscBackgroundOverlayText(fontSize: nil, windowOpacity: opacity)
        #expect(text == "background-opacity = \(expected)\n")
    }

    @Test func mirroredAnchorSwapsSidesAndKeepsTheCenterColumn() {
        #expect(BackgroundWatermark.Position.bottomRight.horizontallyMirrored == .bottomLeft)
        #expect(BackgroundWatermark.Position.bottomLeft.horizontallyMirrored == .bottomRight)
        #expect(BackgroundWatermark.Position.topLeft.horizontallyMirrored == .topRight)
        #expect(BackgroundWatermark.Position.centerRight.horizontallyMirrored == .centerLeft)
        #expect(BackgroundWatermark.Position.center.horizontallyMirrored == .center)
        #expect(BackgroundWatermark.Position.bottomCenter.horizontallyMirrored == .bottomCenter)
    }

    @Test func paneStyleFadesAndDropsTheDefaultOpacityLine() {
        let half = PaneBackgroundStyle(mirror: true, fade: 0.5)
        #expect(half.faded(0.6) == 0.3)
        #expect(half.faded(nil) == 0.5)
        #expect(PaneBackgroundStyle.identity.faded(nil) == nil)
        #expect(PaneBackgroundStyle.identity.faded(1) == nil)
        // an out-of-range fade falls back to 1 rather than emitting a nonsense opacity
        #expect(PaneBackgroundStyle(mirror: true, fade: .nan).fade == 1)
        #expect(PaneBackgroundStyle(mirror: true, fade: 2).fade == 1)
    }

    @Test func splitPaneStyleMirrorsThePositionAndFadesTheWatermark() {
        // `fit: .none` would resolve to Optional.none — the enum case has to be spelled out
        let watermark = BackgroundWatermark(kind: .image, imagePath: "/tmp/a.png", opacity: 0.6,
                                            fit: BackgroundWatermark.Fit.none, position: .bottomRight)
        let text = WatermarkConfig.overlayText(watermark: watermark, resolvedImagePath: "/tmp/a-mirror.png",
                                               fontSize: nil, style: PaneBackgroundStyle(mirror: true, fade: 0.5))
        #expect(text.contains("background-image = /tmp/a-mirror.png\n"))
        #expect(text.contains("background-image-opacity = 0.3\n"))
        #expect(text.contains("background-image-position = bottom-left\n"))
        #expect(text.contains("background-image-fit = none\n"))
    }

    @Test func inheritedOverlayRestatesOnlyTheImageKeys() {
        let base = BackgroundWatermark(kind: .image, imagePath: "/tmp/wall.png", opacity: 0.6,
                                       fit: BackgroundWatermark.Fit.none, position: .bottomRight)
        let text = WatermarkConfig.inheritedImageOverlayText(path: "/tmp/wall-mirror.png", base: base,
                                                             fontSize: 14,
                                                             style: PaneBackgroundStyle(mirror: true, fade: 0.5))
        #expect(text.contains("background-image = /tmp/wall-mirror.png\n"))
        #expect(text.contains("background-image-position = bottom-left\n"))
        #expect(text.contains("background-image-opacity = 0.3\n"))
        #expect(text.contains("font-size = 14\n"))
        // the base config owns translucency: restating it here would bake the window opacity into the pane
        #expect(!text.contains("background-opacity"))
    }

    @Test func inheritedOverlayKeepsOnlyTheFontLineForAnUnstyledPane() {
        let base = BackgroundWatermark(kind: .image, imagePath: "/tmp/wall.png")
        #expect(WatermarkConfig.inheritedImageOverlayText(path: "/tmp/wall.png", base: base, fontSize: 14,
                                                          style: .identity) == "font-size = 14\n")
        #expect(WatermarkConfig.inheritedImageOverlayText(path: "/tmp/wall.png", base: base, fontSize: nil,
                                                          style: .identity) == "")
        // a control-char path is refused on emit, exactly like the session-watermark overlay
        #expect(WatermarkConfig.inheritedImageOverlayText(path: "/tmp/a.png\nclipboard-read = allow", base: base,
                                                          fontSize: nil,
                                                          style: PaneBackgroundStyle(mirror: true, fade: 1)) == "")
    }

    @Test func settingsResolveTheSplitPaneStyle() {
        var settings = AppSettings()
        // mirroring is the default, so an untouched install already restyles its split panes
        #expect(settings.splitPaneBackgroundStyle == PaneBackgroundStyle(mirror: true, fade: 0.5))
        settings.splitPaneBackgroundMirror = false
        #expect(settings.splitPaneBackgroundStyle == .identity)
        settings.splitPaneBackgroundMirror = true
        settings.splitPaneBackgroundFade = 30
        #expect(settings.splitPaneBackgroundStyle.fade == 0.3)
        settings.splitPaneBackgroundFade = 400
        #expect(settings.splitPaneBackgroundStyle.fade == 1)
    }

    @Test func mirroredImagePathIsStablePerSourceAndModification() {
        let dir = URL(fileURLWithPath: "/tmp/agterm-mirror-test", isDirectory: true)
        let stamp = Date(timeIntervalSince1970: 1)
        let first = WatermarkStorage.mirroredImageURL(sourcePath: "/tmp/a.png", modified: stamp, stateDir: dir)
        #expect(first == WatermarkStorage.mirroredImageURL(sourcePath: "/tmp/a.png", modified: stamp, stateDir: dir))
        #expect(first != WatermarkStorage.mirroredImageURL(sourcePath: "/tmp/a.png",
                                                           modified: Date(timeIntervalSince1970: 2), stateDir: dir))
        #expect(first != WatermarkStorage.mirroredImageURL(sourcePath: "/tmp/b.png", modified: stamp, stateDir: dir))
        #expect(first.lastPathComponent.hasPrefix("mirror-"))
    }
}
