import ArgumentParser
import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

/// `agtermctl restore list|open|last|clear` — the reopen verbs beside the capture-clearing one they share a
/// noun with.
struct RestoreCommandsTests {
    private func request(_ argv: [String]) throws -> ControlRequest {
        let parsed = try Agtermctl.parseAsRoot(argv)
        guard let command = parsed as? any RequestCommand else {
            throw SocketClientError("parsed \(argv) is not a RequestCommand")
        }
        return try command.makeRequest()
    }

    @Test func listSendsNoArgsWithoutALimit() throws {
        #expect(try request(["restore", "list"]) == ControlRequest(cmd: .restoreList))
    }

    @Test func listCarriesTheLimit() throws {
        #expect(try request(["restore", "list", "--limit", "5"])
            == ControlRequest(cmd: .restoreList, args: ControlArgs(limit: 5)))
    }

    @Test func openCarriesTheTargetAndWindow() throws {
        #expect(try request(["restore", "open", "2"]) == ControlRequest(cmd: .restoreOpen, target: "2"))
        #expect(try request(["restore", "open", "a1b2", "--window", "w1"])
            == ControlRequest(cmd: .restoreOpen, target: "a1b2", args: ControlArgs(window: "w1")))
    }

    @Test func lastSendsOpenWithNoTarget() throws {
        #expect(try request(["restore", "last"]) == ControlRequest(cmd: .restoreOpen))
    }

    @Test func clearStaysTheCaptureVerb() throws {
        #expect(try request(["restore", "clear"]) == ControlRequest(cmd: .restoreClear))
    }

    @Test func openAndLastEchoTheReopenedSessionID() throws {
        let open = try Agtermctl.parseAsRoot(["restore", "open", "1"]) as? any RequestCommand
        let last = try Agtermctl.parseAsRoot(["restore", "last"]) as? any RequestCommand
        #expect(open?.echoesResultID == true)
        #expect(last?.echoesResultID == true)
    }

    // MARK: - rendering

    private func node(index: Int, id: String, kind: String = "session", title: String,
                      workspace: String? = "mmee", cwd: String? = "/Users/x/mmee",
                      sessions: Int? = nil, restoreCommand: String? = nil) -> ControlRecentClosedNode {
        ControlRecentClosedNode(index: index, id: id, kind: kind, title: title, workspace: workspace, cwd: cwd,
                                closedAt: "2026-09-03T01:02:03+05:00", sessionID: nil, sessions: sessions,
                                restoreCommand: restoreCommand)
    }

    @Test func emptyListReadsAsAStatement() {
        #expect(SocketClient.formatRecentClosed([]) == "no recently closed items")
    }

    @Test func aPinnedSessionRowShowsWhatWillRun() {
        let line = SocketClient.formatRecentClosed([
            node(index: 1, id: "ABCDEF0123456789", title: "agent", restoreCommand: "claude --resume abc")
        ])
        #expect(line == "1  ABCDEF01  2026-09-03T01:02:03+05:00  \"agent\"  → mmee  /Users/x/mmee  ↺ claude --resume abc")
    }

    @Test func anUnpinnedSessionRowCarriesNoCommand() {
        let line = SocketClient.formatRecentClosed([node(index: 2, id: "ABCDEF0123456789", title: "shell")])
        #expect(!line.contains("↺"))
    }

    @Test func aWorkspaceRowCountsItsSessions() {
        let line = SocketClient.formatRecentClosed([
            node(index: 1, id: "ABCDEF0123456789", kind: "workspace", title: "work", workspace: "work",
                 cwd: nil, sessions: 3)
        ])
        #expect(line.contains("(workspace, 3 sessions)"))
    }

    @Test func responseFormattingPrefersTheClosedListOverABareOk() {
        let response = ControlResponse(ok: true, result: ControlResult(closed: [
            node(index: 1, id: "ABCDEF0123456789", title: "agent")
        ]))
        #expect(SocketClient.formatResponse(response, json: false).hasPrefix("1  ABCDEF01"))
    }

    /// `restore open` echoes the new session id, so its response must not fall into the list renderer.
    @Test func openEchoesTheIDRatherThanAList() {
        let response = ControlResponse(ok: true, result: ControlResult(id: "SID"))
        #expect(SocketClient.formatResponse(response, json: false, echoID: true) == "SID")
    }
}
