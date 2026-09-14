import agtermCore
import AppKit
import SwiftUI
import XCTest
@testable import agterm

/// The deck exemptions that make a HUD passive. `DeckPaneGates` and `OverlayPanelStyle` live in the app
/// target, so this cannot be host-free: they are the seam where the same overlay slot renders either a
/// caller's program — which owns first responder, mutes the session and swallows clicks — or a HUD, which
/// does none of it.
@MainActor
final class HudDeckGatesTests: XCTestCase {
    private func makeSession() -> Session { Session(initialCwd: NSTemporaryDirectory()) }

    private func hudSession(position: HudPosition = .center, sizePercent: Int = 40) -> Session {
        let session = makeSession()
        session.overlayActive = true
        session.overlaySizePercent = sizePercent
        session.hudHeightPercent = 12
        session.hudSpec = HudSpec(message: "gathering options…", position: position)
        return session
    }

    private func programSession(sizePercent: Int?) -> Session {
        let session = makeSession()
        session.overlayActive = true
        session.overlaySizePercent = sizePercent
        return session
    }

    // MARK: - cover gate (first responder)

    func testHudLeavesTheSessionUncovered() {
        XCTAssertFalse(DeckPaneGates.coverActive(hudSession()))
    }

    func testProgramOverlayCoversTheSession() {
        XCTAssertTrue(DeckPaneGates.coverActive(programSession(sizePercent: 40)))
        XCTAssertTrue(DeckPaneGates.coverActive(programSession(sizePercent: nil)))
    }

    func testScratchCoversTheSessionWithAHudUp() {
        let session = hudSession()
        session.scratchActive = true
        XCTAssertTrue(DeckPaneGates.coverActive(session))
    }

    func testEmptySlotLeavesTheSessionUncovered() {
        XCTAssertFalse(DeckPaneGates.coverActive(makeSession()))
    }

    func testAHudReplacedByAProgramCoversAgain() {
        let session = hudSession()
        session.hudSpec = nil
        XCTAssertTrue(DeckPaneGates.coverActive(session))
    }

    // MARK: - clicks and backdrop

    func testHudPanelIsInertAndPaintsNoBackdrop() {
        let style = OverlayPanelStyle.resolve(hudSession())
        XCTAssertFalse(style.interactive)
        XCTAssertFalse(style.backdrop)
    }

    func testFloatingProgramOverlayCatchesClicksAndWashesTheBackdrop() {
        let style = OverlayPanelStyle.resolve(programSession(sizePercent: 40))
        XCTAssertTrue(style.interactive)
        XCTAssertTrue(style.backdrop)
    }

    func testFullProgramOverlayIsInteractiveWithoutABackdropWash() {
        let style = OverlayPanelStyle.resolve(programSession(sizePercent: nil))
        XCTAssertTrue(style.interactive)
        XCTAssertFalse(style.backdrop)
    }

    // MARK: - chrome

    // a HUD draws its own text and plate (`HudNoticeView`), so the slot gives it no panel chrome at all
    func testHudCarriesNoPanelChrome() {
        let style = OverlayPanelStyle.resolve(hudSession())
        XCTAssertFalse(style.framed)
        XCTAssertEqual(style.shadowRadius, 0)
        XCTAssertEqual(style.borderOpacity, 0)
        XCTAssertEqual(style.cornerRadius, 0)
    }

    func testFloatingProgramOverlayKeepsItsWindowChrome() {
        let style = OverlayPanelStyle.resolve(programSession(sizePercent: 40))
        XCTAssertTrue(style.framed)
        XCTAssertEqual(style.shadowRadius, 24)
        XCTAssertEqual(style.borderOpacity, 0.18, accuracy: 0.001)
        XCTAssertEqual(style.cornerRadius, 12)
    }

    func testFullProgramOverlayStaysChromeless() {
        let style = OverlayPanelStyle.resolve(programSession(sizePercent: nil))
        XCTAssertFalse(style.framed)
        XCTAssertEqual(style.shadowRadius, 0)
        XCTAssertEqual(style.borderOpacity, 0)
        XCTAssertEqual(style.cornerRadius, 0)
        XCTAssertEqual(style.sizeFraction, 1)
    }

    func testSizePercentBecomesThePaneFraction() {
        XCTAssertEqual(OverlayPanelStyle.resolve(hudSession(sizePercent: 25)).sizeFraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(OverlayPanelStyle.resolve(programSession(sizePercent: 40)).sizeFraction, 0.4, accuracy: 0.0001)
    }

    // MARK: - placement

    func testHudSitsOnItsAnchorAndProgramOverlaysAreAlwaysCentered() {
        XCTAssertEqual(OverlayPanelStyle.resolve(hudSession(position: .topCenter)).position, .topCenter)
        XCTAssertEqual(OverlayPanelStyle.resolve(hudSession(position: .bottomRight)).position, .bottomRight)
        for percent in [nil, 40] as [Int?] {
            XCTAssertEqual(OverlayPanelStyle.resolve(programSession(sizePercent: percent)).position, .center)
        }
    }

    func testEveryAnchorMapsToItsAlignmentAndScaleOrigin() {
        XCTAssertEqual(HudPosition.topLeft.alignment, .topLeading)
        XCTAssertEqual(HudPosition.topCenter.alignment, .top)
        XCTAssertEqual(HudPosition.center.alignment, .center)
        XCTAssertEqual(HudPosition.bottomRight.alignment, .bottomTrailing)
        XCTAssertEqual(HudPosition.centerLeft.alignment, .leading)
        XCTAssertEqual(HudPosition.topLeft.unitPoint, .topLeading)
        XCTAssertEqual(HudPosition.topCenter.unitPoint, .top)
        XCTAssertEqual(HudPosition.center.unitPoint, .center)
        XCTAssertEqual(HudPosition.bottomRight.unitPoint, .bottomTrailing)
    }
}
