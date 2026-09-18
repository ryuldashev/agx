import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct ArtifactCommandsTests {
    @Test func addCarriesEveryOptionAndTheSession() throws {
        let command = try ArtifactCommand.Add.parse([
            "doc/pitch.pdf", "--title", "Pitch", "--source", "open", "--session", "abc", "--cwd", "/w",
            "--agent-session", "t1", "--seen", "2026-09-18T09:00:00Z",
        ])
        #expect(try command.makeRequest() == ControlRequest(
            cmd: .artifactAdd, target: "abc",
            args: ControlArgs(cwd: "/w", title: "Pitch", path: "doc/pitch.pdf", at: "2026-09-18T09:00:00Z",
                              transcript: "t1", source: "open")))
        #expect(command.echoesResultID)
    }

    @Test func addSessionNoneRecordsNoSessionAndCwdDefaultsToTheCurrentDirectory() throws {
        let request = try ArtifactCommand.Add.parse(["/x.pdf", "--session", "none"]).makeRequest()
        #expect(request.target == nil)
        #expect(request.args?.cwd == FileManager.default.currentDirectoryPath)
        #expect(request.args?.path == "/x.pdf")
    }

    @Test func listMapsItsFilters() throws {
        #expect(try ArtifactCommand.List.parse([
            "--query", "pitch", "--workspace", "mars", "--kind", "pdf", "--session", "abc", "--hidden", "--limit", "5",
        ]).makeRequest() == ControlRequest(
            cmd: .artifactList, target: "abc",
            args: ControlArgs(workspace: "mars", query: "pitch", kinds: ["pdf"], limit: 5, all: true)))
        #expect(try ArtifactCommand.List.parse([]).makeRequest() == ControlRequest(cmd: .artifactList, args: ControlArgs()))
    }

    @Test func rowCommandsBuildTheirRequests() throws {
        #expect(try ArtifactCommand.Remove.parse(["a1"]).makeRequest() == ControlRequest(cmd: .artifactRemove, target: "a1"))
        #expect(try ArtifactCommand.Pin.parse(["a1"]).makeRequest()
            == ControlRequest(cmd: .artifactPin, target: "a1", args: ControlArgs()))
        #expect(try ArtifactCommand.Pin.parse(["a1", "--off"]).makeRequest()
            == ControlRequest(cmd: .artifactPin, target: "a1", args: ControlArgs(off: true)))
        #expect(try ArtifactCommand.Hide.parse(["a1", "--off"]).makeRequest()
            == ControlRequest(cmd: .artifactHide, target: "a1", args: ControlArgs(off: true)))
        #expect(try ArtifactCommand.Open.parse(["a1"]).makeRequest()
            == ControlRequest(cmd: .artifactOpen, target: "a1", args: ControlArgs()))
        #expect(try ArtifactCommand.Open.parse(["a1", "--reveal"]).makeRequest()
            == ControlRequest(cmd: .artifactOpen, target: "a1", args: ControlArgs(mode: "reveal")))
        #expect(try ArtifactCommand.Show.parse([]).makeRequest().cmd == .artifactShow)
    }

    @Test func listFormatsOneRowPerLineWithSessionAndDiskState() {
        let node = ControlArtifactNode(
            id: "DCF0D77C-B1D4-4EBF-A7AC-20BE5BD4965A", path: "/a/pitch.pdf", kind: "file", name: "pitch.pdf",
            title: nil, type: "pdf", category: "pdf", seen: "2026-09-18T14:47:30+05:00",
            firstSeen: "2026-09-18T14:47:30+05:00", count: 1, source: "open", session: "Оценка v2",
            sessionID: "S", workspace: "mars", cwd: nil, agentSession: nil, pinned: true, hidden: false,
            exists: true, size: 10)
        let missing = ControlArtifactNode(
            id: "1C959F92-0000-0000-0000-000000000000", path: "/nonexistent/report.pdf", kind: "file",
            name: "report.pdf", title: nil, type: "pdf", category: "pdf", seen: "2026-09-18T14:47:57+05:00",
            firstSeen: "2026-09-18T14:47:57+05:00", count: 1, source: "backfill", session: nil, sessionID: nil,
            workspace: nil, cwd: nil, agentSession: nil, pinned: false, hidden: true, exists: false, size: nil)
        let response = ControlResponse(ok: true, result: ControlResult(artifacts: [node, missing]))
        #expect(SocketClient.formatResponse(response, json: false) == """
            DCF0D77C  2026-09-18T14:47:30+05:00  ★  "pitch.pdf"  → mars › Оценка v2  /a/pitch.pdf
            1C959F92  2026-09-18T14:47:57+05:00     "report.pdf"  /nonexistent/report.pdf  (missing)  (hidden)
            """)
        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: ControlResult(artifacts: [])), json: false)
            == "no artifacts")
    }

    @Test func addEchoesTheIDNotTheRow() {
        let node = ControlArtifactNode(
            id: "X", path: "/a/pitch.pdf", kind: "file", name: "pitch.pdf", title: nil, type: "pdf", category: "pdf",
            seen: "s", firstSeen: "s", count: 1, source: "open", session: nil, sessionID: nil, workspace: nil,
            cwd: nil, agentSession: nil, pinned: false, hidden: false, exists: true, size: nil)
        let response = ControlResponse(ok: true, result: ControlResult(id: "X", artifacts: [node]))
        #expect(SocketClient.formatResponse(response, json: false, echoID: true) == "X")
    }

    @Test func artifactsRoundTripThroughJSONAndOmitWhenNil() throws {
        let node = ControlArtifactNode(
            id: "X", path: "https://x.y", kind: "url", name: "x.y", title: "Site", type: "url", category: "url",
            seen: "s", firstSeen: "s", count: 3, source: "manual", session: nil, sessionID: nil, workspace: nil,
            cwd: nil, agentSession: nil, pinned: false, hidden: false, exists: nil, size: nil)
        let response = ControlResponse(ok: true, result: ControlResult(artifacts: [node]))
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: data) == response)
        let bare = try JSONEncoder().encode(ControlResponse(ok: true, result: ControlResult(id: "x")))
        #expect(!String(decoding: bare, as: UTF8.self).contains("artifacts"))
        let request = ControlRequest(cmd: .artifactAdd, target: "abc",
                                     args: ControlArgs(path: "/x.pdf", source: "open", off: true))
        let requestData = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ControlRequest.self, from: requestData) == request)
    }

    @Test func artifactAddedEventReadsHuman() {
        let event = ControlEvent(seq: 1, ts: 0, kind: .artifactAdded, session: "S",
                                 payload: ControlEventPayload(name: "pitch.pdf", source: "open", path: "/a/pitch.pdf"))
        let line = EventFormatter.human(event, timeZone: TimeZone(identifier: "UTC")!)
        #expect(line == "00:00:00 artifact.added pitch.pdf path=/a/pitch.pdf source=open session=S")
    }
}
