import Foundation
import Testing
@testable import agtermCore

@MainActor
struct ControlDispatcherArtifactTests {
    private func dispatch(_ request: ControlRequest, actions: MockControlActions) async -> ControlResponse {
        await ControlDispatcher(actions: actions).dispatchArtifactCommand(request)
    }

    @Test func addNormalizesTheKeyAndPassesTheRestThrough() async {
        let actions = MockControlActions()
        let request = ControlRequest(cmd: .artifactAdd, target: "abc",
                                     args: ControlArgs(cwd: "/w", title: " Pitch ", path: "doc/../pitch.pdf",
                                                       at: "2026-09-18T09:00:00Z", transcript: "t1", source: "reader"))
        _ = await dispatch(request, actions: actions)
        #expect(actions.calls == [.artifactAdd(ControlArtifactAddOptions(
            path: "/w/pitch.pdf", kind: .file, title: "Pitch", source: .reader,
            seen: Date(timeIntervalSince1970: 1_789_722_000), session: "abc", cwd: "/w", agentSession: "t1"))])
    }

    @Test func addDefaultsToManualNowAndNoSession() async {
        let actions = MockControlActions()
        _ = await dispatch(ControlRequest(cmd: .artifactAdd, args: ControlArgs(path: "https://x.y/z")), actions: actions)
        #expect(actions.calls == [.artifactAdd(ControlArtifactAddOptions(
            path: "https://x.y/z", kind: .url, title: nil, source: .manual, seen: nil,
            session: nil, cwd: nil, agentSession: nil))])
    }

    @Test(arguments: [
        (ControlArgs(), "artifact.add requires a path or URL"),
        (ControlArgs(path: "  "), "artifact.add requires a path or URL"),
        (ControlArgs(path: "doc/x.pdf"),
         "artifact.add: path must be absolute, ~-relative, an http(s) URL, or relative with --cwd"),
        (ControlArgs(title: String(repeating: "a", count: 201), path: "/x.pdf"), "title too long (max 200 characters)"),
        (ControlArgs(path: "/x.pdf", source: "magic"),
         "invalid source: magic (expected open, reader, sendfile, manual, backfill)"),
        (ControlArgs(path: "/x.pdf", at: "yesterday"), "invalid --seen: yesterday (expected ISO 8601)"),
    ])
    func addRejectsWithoutCallingActions(args: ControlArgs, error: String) async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .artifactAdd, args: args), actions: actions)
        #expect(response == ControlResponse(ok: false, error: error))
        #expect(actions.calls.isEmpty)
    }

    @Test func listCarriesFiltersAndTheSessionTarget() async {
        let actions = MockControlActions()
        _ = await dispatch(ControlRequest(cmd: .artifactList, target: "abc",
                                          args: ControlArgs(workspace: "mars", query: " pitch ", kinds: ["pdf"], limit: 5,
                                                            all: true)),
                           actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactList), actions: actions)
        #expect(actions.calls == [
            .artifactList(ControlArtifactListOptions(query: "pitch", workspace: "mars", category: .pdf,
                                                     session: "abc", includeHidden: true, limit: 5)),
            .artifactList(ControlArtifactListOptions(query: nil, workspace: nil, category: nil,
                                                     session: nil, includeHidden: false, limit: nil)),
        ])
    }

    @Test(arguments: [
        (ControlArgs(kinds: ["movie"]),
         "invalid --kind (expected one of pdf, image, document, sheet, slides, media, code, url, other)"),
        (ControlArgs(kinds: ["pdf", "image"]),
         "invalid --kind (expected one of pdf, image, document, sheet, slides, media, code, url, other)"),
        (ControlArgs(limit: 0), "limit must be at least 1"),
    ])
    func listRejectsBadFilters(args: ControlArgs, error: String) async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .artifactList, args: args), actions: actions)
        #expect(response == ControlResponse(ok: false, error: error))
        #expect(actions.calls.isEmpty)
    }

    @Test func rowCommandsRouteTheTargetAndTheOffFlag() async {
        let actions = MockControlActions()
        _ = await dispatch(ControlRequest(cmd: .artifactRemove, target: "a1"), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactPin, target: "a1"), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactPin, target: "a1", args: ControlArgs(off: true)), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactHide, target: "a1"), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactHide, target: "a1", args: ControlArgs(off: true)), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactOpen, target: "a1"), actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactOpen, target: "a1", args: ControlArgs(mode: "reveal")),
                           actions: actions)
        _ = await dispatch(ControlRequest(cmd: .artifactShow, args: ControlArgs(window: "w")), actions: actions)
        #expect(actions.calls == [
            .artifactRemove(target: "a1"),
            .artifactSetPinned(true, target: "a1"), .artifactSetPinned(false, target: "a1"),
            .artifactSetHidden(true, target: "a1"), .artifactSetHidden(false, target: "a1"),
            .artifactOpen(target: "a1", reveal: false), .artifactOpen(target: "a1", reveal: true),
            .artifactShow(window: "w"),
        ])
    }

    @Test(arguments: [Command.artifactRemove, .artifactPin, .artifactHide, .artifactOpen])
    func rowCommandsRequireATarget(cmd: Command) async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: cmd, target: " "), actions: actions)
        #expect(response == ControlResponse(ok: false, error: "\(cmd.rawValue) requires an artifact id or path"))
        #expect(actions.calls.isEmpty)
    }

    @Test func openRejectsAnUnknownMode() async {
        let actions = MockControlActions()
        let response = await dispatch(ControlRequest(cmd: .artifactOpen, target: "a1", args: ControlArgs(mode: "edit")),
                                      actions: actions)
        #expect(response == ControlResponse(ok: false, error: "artifact.open: --mode must be open or reveal"))
        #expect(actions.calls.isEmpty)
    }

    @Test func dispatchRoutesEveryArtifactCommand() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        _ = await dispatcher.dispatch(ControlRequest(cmd: .artifactAdd, args: ControlArgs(path: "/x.pdf")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .artifactList))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .artifactShow))
        #expect(actions.calls.count == 3)
    }

    @Test func parsesISO8601WithAndWithoutFractions() {
        #expect(ControlDispatcher.parseISO8601("2026-09-18T09:00:00Z") == Date(timeIntervalSince1970: 1_789_722_000))
        #expect(ControlDispatcher.parseISO8601("2026-09-18T09:00:00.500Z") == Date(timeIntervalSince1970: 1_789_722_000.5))
        #expect(ControlDispatcher.parseISO8601("2026-09-18T14:00:00+05:00") == Date(timeIntervalSince1970: 1_789_722_000))
        #expect(ControlDispatcher.parseISO8601("2026-09-18") == nil)
    }
}
