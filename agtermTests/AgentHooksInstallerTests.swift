import AppKit
import XCTest
import agtermCore
@testable import agterm

/// NSAlert sizes itself to fit `informativeText`, with no scroll and no height cap, so any text long enough
/// pushes the buttons off the bottom of the screen. Issue #430: the Codex manual-merge cases embedded the
/// whole 29-line hooks block and did exactly that.
@MainActor
final class AgentHooksInstallerTests: XCTestCase {
    private let allResults: [AgentHooksInstaller.IntegrationResult] = [
        .merged, .unchanged, .notInstalled,
        .skipped(reason: "already defines its own hooks", manual: true),
        .skipped(reason: "isn't valid TOML", manual: true),
        .skipped(reason: "exists but couldn't be read", manual: false),
    ]

    private var codex: AgentProfile {
        AgentCatalog.profile(binary: "codex")!
    }

    func testNoOutcomeEmbedsTheHooksBlock() {
        for result in allResults {
            let text = AgentHooksInstaller.agentText(codex, result)
            XCTAssertFalse(text.contains("[[hooks."), "\(result) should point at the docs, not inline the block")
            XCTAssertFalse(text.contains("\n"), "\(result) should stay a single line")
        }
    }

    func testOnlyTheManualMergeOutcomesOfferTheDocsButton() {
        for result in allResults {
            let expected: Bool
            if case .skipped(_, let manual) = result { expected = manual } else { expected = false }
            XCTAssertEqual(result.needsManualMerge, expected, "\(result) offers the docs button: \(expected)")
        }
    }

    func testManualMergeTextNamesTheDocsSection() {
        for result in allResults where result.needsManualMerge {
            XCTAssertTrue(AgentHooksInstaller.agentText(codex, result).contains("Add Codex hooks by hand"),
                          "\(result) should name the docs section the button opens")
        }
    }

    func testMergedTextCarriesTheAgentsActivateStep() {
        let text = AgentHooksInstaller.agentText(codex, .merged)
        XCTAssertTrue(text.contains("~/.codex/config.toml"))
        XCTAssertTrue(text.contains("Run /hooks in Codex"))
    }

    func testDocsButtonIsSecondSoTheDefaultStaysOK() {
        let alert = AgentHooksInstaller.makeAlert(style: .warning, title: "t", text: "x",
                                                  docs: AgentHooksInstaller.codexManualDocsURL)
        XCTAssertEqual(alert.buttons.map(\.title), ["OK", "Open Docs"])
    }

    func testAlertWithoutDocsKeepsTheSingleDefaultButton() {
        let alert = AgentHooksInstaller.makeAlert(style: .informational, title: "t", text: "x", docs: nil)
        XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
    }

    func testDocsURLPointsAtTheManualMergeAnchor() throws {
        let url = try XCTUnwrap(AgentHooksInstaller.codexManualDocsURL)
        XCTAssertEqual(url.absoluteString, "https://agterm.com/docs#codex-hooks-manual")
    }
}
