import Foundation
import Testing
@testable import agtermCore

@MainActor
struct ControlDispatcherUpdateTests {
    @Test(arguments: [
        (Command.updateCheck, MockControlActions.Call.updateCheck),
        (Command.updateStatus, MockControlActions.Call.updateStatus),
        (Command.updateInstall, MockControlActions.Call.updateInstall),
    ])
    func updateCommandsRouteStraightToTheApp(command: Command, call: MockControlActions.Call) async {
        let actions = MockControlActions()
        let node = ControlUpdateNode(version: "0.24.0", state: "available", available: "0.25.0", automatic: true)
        actions.nextUpdateResponse = ControlResponse(ok: true, result: ControlResult(update: node))
        let response = await ControlDispatcher(actions: actions).dispatch(ControlRequest(cmd: command))
        #expect(response == ControlResponse(ok: true, result: ControlResult(update: node)))
        #expect(actions.calls == [call])
    }

    @Test func updateCommandsRoundTripOnTheWire() throws {
        for command in [Command.updateCheck, .updateStatus, .updateInstall] {
            let request = ControlRequest(cmd: command)
            let decoded = try JSONDecoder().decode(ControlRequest.self, from: JSONEncoder().encode(request))
            #expect(decoded == request)
        }
        #expect(Command.updateCheck.rawValue == "update.check")
        #expect(Command.updateStatus.rawValue == "update.status")
        #expect(Command.updateInstall.rawValue == "update.install")
    }
}
