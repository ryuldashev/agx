import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct UpdateCommandsTests {
    @Test func subcommandsBuildTheirRequests() throws {
        #expect(try Update.Check.parse([]).makeRequest() == ControlRequest(cmd: .updateCheck))
        #expect(try Update.Status.parse([]).makeRequest() == ControlRequest(cmd: .updateStatus))
        #expect(try Update.Install.parse([]).makeRequest() == ControlRequest(cmd: .updateInstall))
    }

    @Test func updateResultPrintsTheNodeLine() {
        let node = ControlUpdateNode(version: "0.24.0", state: "available", available: "0.25.0", automatic: true)
        let response = ControlResponse(ok: true, result: ControlResult(update: node))
        #expect(SocketClient.formatResponse(response, json: false) == node.humanDescription)
    }

    @Test func eventsFormatUpdateKinds() {
        let event = ControlEvent(seq: 1, ts: 0, kind: .updateAvailable,
                                 payload: ControlEventPayload(name: "agx", version: "0.25.0"))
        #expect(EventFormatter.human(event, timeZone: TimeZone(identifier: "UTC")!) == "00:00:00 update.available 0.25.0")
    }
}
