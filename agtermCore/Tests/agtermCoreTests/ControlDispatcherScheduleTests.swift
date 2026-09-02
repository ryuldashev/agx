import Foundation
import Testing
@testable import agtermCore

@MainActor
struct ControlDispatcherScheduleTests {
    private let now = ISO8601DateFormatter().date(from: "2026-09-02T19:20:00Z")!

    private func dispatch(_ request: ControlRequest, actions: MockControlActions) -> ControlResponse {
        ControlDispatcher(actions: actions).dispatchScheduleCommand(request, now: now)
    }

    @Test func addParsesTimeAndRoutesTheRest() {
        let actions = MockControlActions()
        actions.nextScheduleResponse = ControlResponse(ok: true, result: ControlResult(id: "job"))
        let response = dispatch(ControlRequest(cmd: .scheduleAdd, args: ControlArgs(
            name: " Spend ", cwd: "/tmp", workspaceName: "mmee", noSelect: true, window: "win",
            agent: "Claude Code", at: "+2h", brief: "do it")), actions: actions)
        #expect(response == ControlResponse(ok: true, result: ControlResult(id: "job")))
        #expect(actions.calls == [.scheduleAdd(ControlScheduleAddOptions(
            window: "win", fireAt: now.addingTimeInterval(7200), brief: "do it", name: "Spend", workspace: nil,
            workspaceName: "mmee", cwd: "/tmp", agent: "Claude Code", command: nil, foreground: false))])
    }

    @Test func addDefaultsToForeground() {
        let actions = MockControlActions()
        _ = dispatch(ControlRequest(cmd: .scheduleAdd, args: ControlArgs(at: "+1m", brief: "b")), actions: actions)
        guard case .scheduleAdd(let options)? = actions.calls.first else { Issue.record("no add call"); return }
        #expect(options.foreground)
        #expect(options.workspace == nil && options.workspaceName == nil && options.agent == nil)
    }

    @Test(arguments: [
        (ControlArgs(at: "+1m"), "schedule.add requires a brief"),
        (ControlArgs(at: "+1m", brief: "  \n"), "schedule.add requires a brief"),
        (ControlArgs(brief: "b"), "schedule.add requires --at (\(ScheduleTime.acceptedForms))"),
        (ControlArgs(at: "soon", brief: "b"), "invalid time: soon (\(ScheduleTime.acceptedForms))"),
        (ControlArgs(at: "2026-01-01 10:00", brief: "b"), "time is in the past: 2026-01-01 10:00"),
        (ControlArgs(workspace: "w", workspaceName: "n", at: "+1m", brief: "b"), "use either --workspace or --workspace-name, not both"),
        (ControlArgs(command: "top", agent: "a", at: "+1m", brief: "b"), "use either --agent or --command, not both"),
        (ControlArgs(name: "a\u{1b}b", at: "+1m", brief: "b"), "name must not contain control characters"),
    ])
    func addRejectsWithoutCallingActions(args: ControlArgs, error: String) {
        let actions = MockControlActions()
        let response = dispatch(ControlRequest(cmd: .scheduleAdd, args: args), actions: actions)
        #expect(response == ControlResponse(ok: false, error: error))
        #expect(actions.calls.isEmpty)
    }

    @Test func listCancelAndRunRoute() {
        let actions = MockControlActions()
        _ = dispatch(ControlRequest(cmd: .scheduleList), actions: actions)
        _ = dispatch(ControlRequest(cmd: .scheduleCancel, target: "abc"), actions: actions)
        _ = dispatch(ControlRequest(cmd: .scheduleRun, target: "def"), actions: actions)
        #expect(actions.calls == [.scheduleList, .scheduleCancel(target: "abc"), .scheduleRun(target: "def")])
    }

    @Test func cancelAndRunRequireATarget() {
        let actions = MockControlActions()
        #expect(dispatch(ControlRequest(cmd: .scheduleCancel), actions: actions)
            == ControlResponse(ok: false, error: "schedule.cancel requires a schedule id"))
        #expect(dispatch(ControlRequest(cmd: .scheduleRun, target: " "), actions: actions)
            == ControlResponse(ok: false, error: "schedule.run requires a schedule id"))
        #expect(actions.calls.isEmpty)
    }

    @Test func topLevelDispatchReachesTheScheduleFamily() async {
        let actions = MockControlActions()
        let response = await ControlDispatcher(actions: actions).dispatch(ControlRequest(cmd: .scheduleList))
        #expect(response == ControlResponse(ok: true))
        #expect(actions.calls == [.scheduleList])
    }

    @Test func scheduleRequestsAndNodesRoundTrip() throws {
        let request = ControlRequest(cmd: .scheduleAdd, args: ControlArgs(
            name: "n", cwd: "/c", workspace: "w", noSelect: true, command: "top", at: "tomorrow 10:00", brief: "b"))
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ControlRequest.self, from: data) == request)

        let node = ControlScheduledNode(id: "id", name: "n", at: "2026-09-04T10:00:00+05:00", inSeconds: 10, state: "pending",
                                        workspace: "w", workspaceID: "wid", cwd: "/c", launch: nil, foreground: true, brief: "b")
        let response = ControlResponse(ok: true, result: ControlResult(id: "id", scheduled: [node]))
        let encoded = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: encoded) == response)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("\"launch\""))
    }
}
