import Foundation
import Testing
@testable import agtermCore

/// The `restore.list` / `restore.open` wire surface: projection, target resolution, and dispatch.
@MainActor
final class RecentClosedControlTests {
    private func sessionItem(title: String, workspace: String = "work", cwd: String = "/a",
                             restoreCommand: String? = nil, id: UUID = UUID(),
                             sessionID: UUID = UUID(), closedAt: Date = Date()) -> RecentClosedItem {
        RecentClosedItem(
            id: id, kind: .session, title: title, subtitle: workspace, closedAt: closedAt,
            session: RecentClosedSession(
                workspaceID: UUID(), workspaceName: workspace, workspaceIndex: 0, sessionIndex: 0,
                snapshot: SessionSnapshot(id: sessionID, customName: title, cwd: cwd, isSplit: false,
                                          restoreCommand: restoreCommand)))
    }

    private func workspaceItem(title: String, sessions: Int, id: UUID = UUID()) -> RecentClosedItem {
        let snapshots = (0..<sessions).map {
            SessionSnapshot(id: UUID(), customName: "s\($0)", cwd: "/a", isSplit: false)
        }
        return RecentClosedItem(
            id: id, kind: .workspace, title: title, subtitle: "\(sessions) sessions",
            workspace: RecentClosedWorkspace(
                snapshot: WorkspaceSnapshot(id: UUID(), name: title, sessions: snapshots),
                selectedSessionID: nil))
    }

    // MARK: - projection

    @Test func projectionCarriesTheAgentPinThatDecidesWhatComesBack() {
        let item = sessionItem(title: "agent", workspace: "mmee", cwd: "/Users/x/mmee",
                               restoreCommand: "zsh -lc 'exec claude --resume abc'")
        let node = ControlRecentClosedNode.project(item, index: 1)

        #expect(node.index == 1)
        #expect(node.id == item.id.uuidString)
        #expect(node.kind == "session")
        #expect(node.title == "agent")
        #expect(node.workspace == "mmee")
        #expect(node.cwd == "/Users/x/mmee")
        #expect(node.sessionID == item.session?.snapshot.id.uuidString)
        #expect(node.restoreCommand == "zsh -lc 'exec claude --resume abc'")
        #expect(node.sessions == nil)
    }

    /// `""` is `session.restore --none` — a deliberate plain shell, which answers the same question as no
    /// pin at all, so the node reports neither as a command.
    @Test func projectionReportsAPinnedPlainShellAsNoCommand() {
        #expect(ControlRecentClosedNode.project(sessionItem(title: "s", restoreCommand: ""), index: 1)
            .restoreCommand == nil)
        #expect(ControlRecentClosedNode.project(sessionItem(title: "s"), index: 1).restoreCommand == nil)
    }

    @Test func projectionOfAWorkspaceCarriesItsMemberCount() {
        let node = ControlRecentClosedNode.project(workspaceItem(title: "work", sessions: 3), index: 2)
        #expect(node.kind == "workspace")
        #expect(node.sessions == 3)
        #expect(node.workspace == "work")
        #expect(node.sessionID == nil)
        #expect(node.cwd == nil)
    }

    @Test func projectionTimestampIsISO8601WithTheLocalOffset() {
        let node = ControlRecentClosedNode.project(
            sessionItem(title: "s", closedAt: Date(timeIntervalSince1970: 0)), index: 1,
            timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(node.closedAt == "1970-01-01T00:00:00Z")
    }

    // MARK: - resolution

    @Test func resolvesThePrintedIndex() throws {
        let items = [sessionItem(title: "newest"), sessionItem(title: "older")]
        #expect(RecentClosedResolve.resolve("1", items: items) == .resolved(items[0].id))
        #expect(RecentClosedResolve.resolve("2", items: items) == .resolved(items[1].id))
    }

    @Test func rejectsAnIndexOutsideTheList() {
        let items = [sessionItem(title: "only")]
        #expect(RecentClosedResolve.resolve("2", items: items) == .notFound)
        #expect(RecentClosedResolve.resolve("0", items: items) == .notFound)
        #expect(RecentClosedResolve.resolve("", items: items) == .notFound)
        #expect(RecentClosedResolve.resolve("1", items: []) == .notFound)
    }

    /// An out-of-range index must not fall through to prefix matching: entry ids are hex, so a one-item list
    /// whose id starts with `2` would answer `restore open 2` by reopening entry 1.
    @Test func anOutOfRangeIndexNeverFallsThroughToAnIDPrefix() throws {
        let item = sessionItem(title: "only", id: try #require(UUID(uuidString: "2AA1AE81-0000-0000-0000-000000000001")))
        #expect(RecentClosedResolve.resolve("2", items: [item]) == .notFound)
        #expect(RecentClosedResolve.resolve("2a", items: [item]) == .resolved(item.id))
    }

    @Test func resolvesTheEntryIDAndItsPrefix() {
        let item = sessionItem(title: "s")
        let items = [item]
        #expect(RecentClosedResolve.resolve(item.id.uuidString, items: items) == .resolved(item.id))
        #expect(RecentClosedResolve.resolve(String(item.id.uuidString.prefix(8)).lowercased(),
                                            items: items) == .resolved(item.id))
    }

    /// The id a caller last saw in `tree` is the CLOSED SESSION's, not the entry's, so it has to resolve too.
    @Test func resolvesTheClosedSessionsOwnID() {
        let sessionID = UUID()
        let item = sessionItem(title: "s", sessionID: sessionID)
        #expect(RecentClosedResolve.resolve(sessionID.uuidString, items: [item]) == .resolved(item.id))
        #expect(RecentClosedResolve.resolve(String(sessionID.uuidString.prefix(8)).lowercased(),
                                            items: [item]) == .resolved(item.id))
    }

    @Test func reportsAnAmbiguousSessionPrefix() throws {
        let shared = "AAAAAAAA"
        let first = sessionItem(title: "a", sessionID: try #require(UUID(uuidString: "\(shared)-0000-0000-0000-000000000001")))
        let second = sessionItem(title: "b", sessionID: try #require(UUID(uuidString: "\(shared)-0000-0000-0000-000000000002")))
        #expect(RecentClosedResolve.resolve(shared.lowercased(), items: [first, second])
            == .ambiguous([first.id, second.id]))
    }

    // MARK: - dispatch

    @Test func listPassesTheLimitThrough() async {
        let actions = MockControlActions()
        let response = await ControlDispatcher(actions: actions)
            .dispatch(ControlRequest(cmd: .restoreList, args: ControlArgs(limit: 5)))
        #expect(response?.ok == true)
        #expect(actions.calls == [.restoreList(limit: 5)])
    }

    @Test func listRejectsANonPositiveLimit() async {
        let actions = MockControlActions()
        let response = await ControlDispatcher(actions: actions)
            .dispatch(ControlRequest(cmd: .restoreList, args: ControlArgs(limit: 0)))
        #expect(response?.ok == false)
        #expect(response?.error == "--limit must be greater than 0")
        #expect(actions.calls.isEmpty)
    }

    @Test func openPassesTheTargetAndWindowThrough() async {
        let actions = MockControlActions()
        let response = await ControlDispatcher(actions: actions)
            .dispatch(ControlRequest(cmd: .restoreOpen, target: "2", args: ControlArgs(window: "w1")))
        #expect(response?.ok == true)
        #expect(actions.calls == [.restoreOpen(target: "2", window: "w1")])
    }

    /// `restore last` is `restore.open` with no target at all, and only that means the newest entry.
    @Test func openWithoutATargetMeansTheNewest() async {
        let actions = MockControlActions()
        _ = await ControlDispatcher(actions: actions).dispatch(ControlRequest(cmd: .restoreOpen))
        #expect(actions.calls == [.restoreOpen(target: nil, window: nil)])
    }

    /// An unset shell variable reaches the socket as `""`. Reopening "whatever is newest" for it would run a
    /// pinned command the caller never named and consume the entry.
    @Test func openWithABlankTargetIsRejectedRatherThanTakenAsTheNewest() async {
        let actions = MockControlActions()
        let response = await ControlDispatcher(actions: actions)
            .dispatch(ControlRequest(cmd: .restoreOpen, target: "  "))
        #expect(response?.ok == false)
        #expect(response?.error == "restore.open target must not be blank")
        #expect(actions.calls.isEmpty)
    }
}
