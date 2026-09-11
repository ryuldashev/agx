import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct SessionFailureCommandsTests {
    @Test func buildsTheRequestFromFlags() throws {
        let command = try Session.Failure.parse(["rate_limit", "--message", "out of credits", "--transcript", "/t/a.jsonl",
                                                 "--handoff", "--target", "S", "--window", "win"])
        let request = try command.makeRequest()
        #expect(request.cmd == .sessionFailure)
        #expect(request.target == "S")
        #expect(request.args == ControlArgs(message: "out of credits", window: "win", error: "rate_limit",
                                            transcript: "/t/a.jsonl", handoff: true))
    }

    @Test func handoffIsOmittedWhenNotAsked() throws {
        let request = try Session.Failure.parse(["server_error"]).makeRequest()
        #expect(request.args?.handoff == nil)
        #expect(request.args?.message == nil)
    }

    @Test func requiresTheErrorType() {
        #expect(throws: (any Error).self) { try Session.Failure.parse([]) }
    }

    @Test func humanOutputNamesTheAction() {
        let switched = ControlResponse(ok: true, result: ControlResult(id: "S", failover: ControlFailoverNode(
            lastAction: "switch-model", switchedTo: "opus[1m]")))
        #expect(SocketClient.formatResponse(switched, json: false) == "switch-model opus[1m]")
        let handoff = ControlResponse(ok: true, result: ControlResult(id: "S", failover: ControlFailoverNode(
            lastAction: "handoff", handedOffTo: "NEW")))
        #expect(SocketClient.formatResponse(handoff, json: false) == "handoff session NEW")
    }

    @Test func failoverEventReadsHuman() {
        let event = ControlEvent(seq: 1, ts: 0, kind: .failover, session: "NEW",
                                 payload: ControlEventPayload(name: "Payroll", action: "handoff", reason: "limit", source: "OLD"))
        let line = EventFormatter.human(event, timeZone: TimeZone(identifier: "UTC")!)
        #expect(line == "00:00:00 failover Payroll handoff source=OLD session=NEW reason=limit")
    }
}
