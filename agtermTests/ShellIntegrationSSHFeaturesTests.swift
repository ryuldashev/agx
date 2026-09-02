import XCTest
@testable import agterm

/// The ssh features must never survive into a spawned shell: agx has no `ghostty` binary for the shell
/// integration's `ssh` wrapper to exec, so leaving them on breaks `ssh` in every pane.
@MainActor
final class ShellIntegrationSSHFeaturesTests: XCTestCase {
    private var scoped: URL!

    override func setUpWithError() throws {
        scoped = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("agterm-ssh-features-\(UUID().uuidString).conf")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scoped)
    }

    private func resolve(_ conf: String) throws -> String? {
        try conf.write(to: scoped, atomically: true, encoding: .utf8)
        return GhosttyApp.sshFreeShellIntegrationFeatures(scopedPath: scoped.path, inheritGlobalConfig: false)
    }

    func testStripsSSHFeaturesAndKeepsTheRest() throws {
        let features = try resolve("shell-integration-features = cursor,sudo,title,ssh-env,ssh-terminfo\n")
        XCTAssertEqual(features, "cursor,sudo,title,no-ssh-env,no-ssh-terminfo")
    }

    func testLeavesAnSSHFreeSetAlone() throws {
        XCTAssertNil(try resolve("shell-integration-features = cursor,sudo,title\n"))
    }

    func testLastAssignmentWins() throws {
        let features = try resolve("""
        shell-integration-features = cursor,ssh-terminfo
        # a later assignment replaces the whole set rather than merging into it
        shell-integration-features = title,ssh-env
        """)
        XCTAssertEqual(features, "title,no-ssh-env,no-ssh-terminfo")
    }
}
