import Foundation
import Testing
@testable import agtermCore

@MainActor
struct ControlDispatcherSecretTests {
    private func dispatch(_ request: ControlRequest, actions: MockControlActions) async -> ControlResponse {
        await ControlDispatcher(actions: actions).dispatchSecretCommand(request)
    }

    @Test func addTrimsTheLabelAndPassesTheValueThrough() async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .secretAdd, args: ControlArgs(label: " root@db ", value: "p4ss w0rd")),
                                      actions: actions)
        #expect(response == ControlResponse(ok: true))
        #expect(actions.calls == [.secretAdd(label: "root@db", value: "p4ss w0rd")])
    }

    @Test(arguments: [
        (ControlArgs(value: "v"), "secret.add requires a label"),
        (ControlArgs(label: "  ", value: "v"), "secret.add requires a label"),
        (ControlArgs(label: String(repeating: "a", count: 65), value: "v"), "label too long (max 64 characters)"),
        (ControlArgs(label: "a\tb", value: "v"), "label must not contain control characters"),
        (ControlArgs(label: "root"), "secret.add requires a value"),
        (ControlArgs(label: "root", value: ""), "secret.add requires a value"),
        (ControlArgs(label: "root", value: String(repeating: "x", count: 4097)), "value too long (max 4096 characters)"),
        (ControlArgs(label: "root", value: "a\nb"), "value must not contain control characters"),
    ])
    func addRejectsWithoutCallingActions(args: ControlArgs, error: String) async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .secretAdd, args: args), actions: actions)
        #expect(response == ControlResponse(ok: false, error: error))
        #expect(actions.calls.isEmpty)
    }

    @Test func removeAndListRoute() async {
        let actions = MockControlActions()
        _ = await dispatch(ControlRequest(cmd: .secretList), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .secretRemove, args: ControlArgs(label: "root")), actions: actions)
        #expect(actions.calls == [.secretList, .secretRemove(label: "root")])
    }

    @Test func removeRequiresALabel() async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .secretRemove), actions: actions)
        #expect(response == ControlResponse(ok: false, error: "secret.remove requires a label"))
        #expect(actions.calls.isEmpty)
    }

    @Test func insertRoutesTargetWindowAndPane() async {
        let actions = MockControlActions()
        _ = await dispatch(ControlRequest(cmd: .secretInsert, target: "abc",
                                          args: ControlArgs(window: "win", pane: "right", label: "root")),
                           actions: actions)
        #expect(actions.calls == [.secretInsert(label: "root", target: "abc", window: "win", pane: "right")])
    }

    @Test func insertRejectsAnUnknownPane() async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .secretInsert, args: ControlArgs(pane: "other", label: "root")),
                                      actions: actions)
        #expect(response == ControlResponse(ok: false, error: "invalid pane: other"))
        #expect(actions.calls.isEmpty)
    }

    @Test func dispatchRoutesEverySecretCommand() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        _ = await dispatcher.dispatch(ControlRequest(cmd: .secretList))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .secretAdd, args: ControlArgs(label: "a", value: "b")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .secretRemove, args: ControlArgs(label: "a")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .secretInsert, args: ControlArgs(label: "a")))
        #expect(actions.calls == [.secretList, .secretAdd(label: "a", value: "b"), .secretRemove(label: "a"),
                                  .secretInsert(label: "a", target: nil, window: nil, pane: nil)])
    }
}
