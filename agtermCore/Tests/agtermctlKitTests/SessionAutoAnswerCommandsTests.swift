import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct SessionAutoAnswerCommandsTests {
    @Test func buildsTheRequestFromTheMode() throws {
        let request = try Session.AutoAnswer.parse(["off", "--target", "S", "--window", "win"]).makeRequest()
        #expect(request.cmd == .sessionAutoAnswer)
        #expect(request.target == "S")
        #expect(request.args == ControlArgs(mode: "off", window: "win"))
    }

    @Test func statusIsTheDefaultMode() throws {
        let request = try Session.AutoAnswer.parse([]).makeRequest()
        #expect(request.args?.mode == "status")
    }

    @Test func rejectsAnUnknownMode() {
        #expect(throws: (any Error).self) { try Session.AutoAnswer.parse(["toggle"]) }
    }

    @Test func humanOutputReadsTheState() {
        let plain = ControlResponse(ok: true, result: ControlResult(id: "S", autoAnswer: ControlAutoAnswerNode(
            enabled: true, source: "settings", delaySeconds: 45)))
        #expect(SocketClient.formatResponse(plain, json: false) == "on (settings) 45s")
        let held = ControlResponse(ok: true, result: ControlResult(id: "S", autoAnswer: ControlAutoAnswerNode(
            enabled: false, source: "session", delaySeconds: 45, dueAt: "2026-09-15T10:00:00+05:00",
            held: 1, lastAction: "held", lastReason: "destructive: sudo")))
        #expect(SocketClient.formatResponse(held, json: false) == "off (session) 45s due 2026-09-15T10:00:00+05:00 last held (destructive: sudo)")
    }

    @Test func autoAnswerEventReadsHuman() {
        let event = ControlEvent(seq: 1, ts: 0, kind: .autoAnswer, session: "S",
                                 payload: ControlEventPayload(name: "Payroll", action: "held", reason: "destructive: rm -rf", agent: "claude"))
        let line = EventFormatter.human(event, timeZone: TimeZone(identifier: "UTC")!)
        #expect(line == "00:00:00 auto_answer Payroll held agent=claude session=S reason=destructive: rm -rf")
    }
}
