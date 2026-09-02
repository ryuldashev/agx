import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

struct ScheduleCommandsTests {
    private let node = ControlScheduledNode(id: "0123456789ABCDEF", name: "Spend", at: "2026-09-04T10:00:00+05:00",
                                            inSeconds: 34_200, state: "pending", workspace: "mmee", workspaceID: nil,
                                            cwd: nil, launch: nil, foreground: true, brief: "b")

    @Test func addBuildsTheRequestFromFlags() throws {
        let command = try Schedule.Add.parse(["--at", "tomorrow 10:00", "--brief", "read the plan", "--name", "Spend",
                                              "--workspace-name", "mmee", "--cwd", "/tmp", "--agent", "Claude Code",
                                              "--background", "--window", "win"])
        let request = try command.makeRequest()
        #expect(request.cmd == .scheduleAdd)
        #expect(request.args == ControlArgs(name: "Spend", cwd: "/tmp", workspaceName: "mmee", noSelect: true,
                                            window: "win", agent: "Claude Code", at: "tomorrow 10:00", brief: "read the plan"))
        #expect(command.echoesResultID)
    }

    @Test func addRequiresExactlyOneBriefSource() {
        #expect(throws: (any Error).self) { try Schedule.Add.parse(["--at", "+1m"]) }
        #expect(throws: (any Error).self) { try Schedule.Add.parse(["--at", "+1m", "--brief", "a", "--brief-file", "/f"]) }
    }

    @Test func addReadsTheBriefFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("brief-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("line one\nline two".utf8).write(to: file)
        let command = try Schedule.Add.parse(["--at", "+1m", "--brief-file", file.path, "--workspace", "w"])
        #expect(try command.makeRequest().args?.brief == "line one\nline two")
        #expect(try command.makeRequest().args?.workspace == "w")
    }

    @Test func cancelAndRunTakeAnId() throws {
        #expect(try Schedule.Cancel.parse(["abc"]).makeRequest() == ControlRequest(cmd: .scheduleCancel, target: "abc"))
        #expect(try Schedule.Run.parse(["abc"]).makeRequest() == ControlRequest(cmd: .scheduleRun, target: "abc"))
        #expect(try Schedule.List.parse([]).makeRequest() == ControlRequest(cmd: .scheduleList))
    }

    @Test func listFormatsOneLinePerJob() {
        var missed = node
        missed = ControlScheduledNode(id: "FEDCBA9876543210", name: nil, at: "2026-09-01T10:00:00+05:00", inSeconds: -90_000,
                                      state: "missed", workspace: nil, workspaceID: nil, cwd: nil, launch: nil,
                                      foreground: false, brief: "b")
        let response = ControlResponse(ok: true, result: ControlResult(scheduled: [node, missed]))
        #expect(SocketClient.formatResponse(response, json: false) == """
            01234567  2026-09-04T10:00:00+05:00  in 9h 30m  → mmee  "Spend"
            FEDCBA98  2026-09-01T10:00:00+05:00  1d 1h ago  (missed)
            """)
        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: ControlResult(scheduled: [])), json: false)
            == "no scheduled sessions")
    }

    @Test func addEchoesTheIdOverTheListing() {
        let response = ControlResponse(ok: true, result: ControlResult(id: "job-id", scheduled: [node]))
        #expect(SocketClient.formatResponse(response, json: false, echoID: true) == "job-id")
    }

    @Test(arguments: [(45, "in 45s"), (600, "in 10m"), (3_660, "in 1h 1m"), (-30, "30s ago"), (172_800, "in 2d 0h")])
    func countdownRounds(seconds: Int, expected: String) {
        #expect(SocketClient.countdown(seconds) == expected)
    }

    @Test func eventsFormatScheduleKinds() {
        let event = ControlEvent(seq: 1, ts: 0, kind: .scheduleFired, session: "S",
                                 payload: ControlEventPayload(name: "Spend", at: "2026-09-04T10:00:00+05:00"))
        #expect(EventFormatter.human(event, timeZone: TimeZone(identifier: "UTC")!)
            == "00:00:00 schedule.fired Spend at=2026-09-04T10:00:00+05:00 session=S")
    }
}
