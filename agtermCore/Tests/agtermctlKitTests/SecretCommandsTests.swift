import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct SecretCommandsTests {
    @Test func addCarriesTheLabelAndTheValueReadElsewhere() throws {
        let command = try Secret.Add.parse(["root@db"])
        #expect(command.request(value: "hunter2")
            == ControlRequest(cmd: .secretAdd, args: ControlArgs(label: "root@db", value: "hunter2")))
    }

    @Test func removeAndListBuildTheirRequests() throws {
        #expect(try Secret.Remove.parse(["root"]).makeRequest()
            == ControlRequest(cmd: .secretRemove, args: ControlArgs(label: "root")))
        #expect(try Secret.List.parse([]).makeRequest() == ControlRequest(cmd: .secretList))
    }

    @Test func insertDefaultsToTheActiveSessionAndMainPane() throws {
        #expect(try Secret.Insert.parse(["root"]).makeRequest()
            == ControlRequest(cmd: .secretInsert, target: "active", args: ControlArgs(label: "root")))
        #expect(try Secret.Insert.parse(["root", "--target", "abc", "--pane", "right", "--window", "w"]).makeRequest()
            == ControlRequest(cmd: .secretInsert, target: "abc",
                              args: ControlArgs(window: "w", pane: "right", label: "root")))
    }

    @Test func listPrintsOneLabelPerLine() {
        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: ControlResult(secrets: ["db", "root"])),
                                            json: false) == "db\nroot")
        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: ControlResult(secrets: [])), json: false)
            == "no secrets")
    }

    @Test func secretsRoundTripThroughJSONAndOmitWhenNil() throws {
        let response = ControlResponse(ok: true, result: ControlResult(secrets: ["root"]))
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: data) == response)
        let bare = try JSONEncoder().encode(ControlResponse(ok: true, result: ControlResult(id: "x")))
        #expect(!String(decoding: bare, as: UTF8.self).contains("secrets"))
        let request = ControlRequest(cmd: .secretAdd, args: ControlArgs(label: "root", value: "v"))
        let requestData = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ControlRequest.self, from: requestData) == request)
    }
}
