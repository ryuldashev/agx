import AppKit
import XCTest
import agtermCore
@testable import agterm

/// The result window shows one plain line per agent. Issue #430: the alert this replaced embedded the whole
/// 29-line Codex hooks block and grew past the bottom of the screen — nothing here may inline it.
@MainActor
final class AgentHooksInstallerTests: XCTestCase {
    private let allResults: [AgentHooksInstaller.IntegrationResult] = [
        .merged, .unchanged, .notInstalled,
        .skipped(reason: "already defines its own hooks", manual: true),
        .skipped(reason: "isn't valid TOML", manual: true),
        .skipped(reason: "exists but couldn't be read", manual: false),
    ]

    private var codex: AgentProfile { AgentCatalog.profile(binary: "codex")! }

    func testNoDetailEmbedsTheHooksBlockOrAHomePath() {
        for result in allResults {
            let detail = AgentHooksInstaller.Row(profile: codex, result: result).detail
            XCTAssertFalse(detail.contains("[[hooks."), "\(result) should point at the docs, not inline the block")
            XCTAssertFalse(detail.contains("\n"), "\(result) should stay a single line")
            XCTAssertFalse(detail.contains("/Users/"), "\(result) should not print a home path")
        }
    }

    func testOnlyTheManualMergeOutcomesOfferTheDocsButton() {
        for result in allResults {
            let expected: Bool
            if case .skipped(_, let manual) = result { expected = manual } else { expected = false }
            XCTAssertEqual(result.needsManualMerge, expected, "\(result) offers the docs button: \(expected)")
        }
    }

    func testSkippedDetailNamesTheFileNotItsPath() {
        let detail = AgentHooksInstaller.Row(profile: codex, result: .skipped(reason: "isn't valid TOML", manual: true)).detail
        XCTAssertTrue(detail.hasPrefix("config.toml isn't valid TOML"))
        XCTAssertTrue(detail.contains("docs"))
    }

    func testMergedDetailCarriesTheAgentsActivateStep() {
        XCTAssertEqual(AgentHooksInstaller.Row(profile: codex, result: .merged).detail,
                       "Hooks added. Run /hooks in Codex to review and approve them before they take effect.")
        let opencode = AgentCatalog.profile(binary: "opencode")!
        XCTAssertTrue(AgentHooksInstaller.Row(profile: opencode, result: .merged).detail.hasPrefix("Plugin installed."))
    }

    func testDocsURLPointsAtTheManualMergeAnchor() throws {
        let url = try XCTUnwrap(AgentHooksInstaller.codexManualDocsURL)
        XCTAssertEqual(url.absoluteString, "https://agterm.com/docs#codex-hooks-manual")
    }
}
