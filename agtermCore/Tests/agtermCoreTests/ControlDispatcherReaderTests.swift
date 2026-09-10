import Foundation
import Testing
@testable import agtermCore

@MainActor
struct ControlDispatcherReaderTests {
    @Test func openRejectsMissingAndBlankPathWithoutCallingHost() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let missing = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderOpen))
        let blank = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderOpen, args: ControlArgs(path: "  ")))

        let expected = ControlResponse(ok: false, error: "session.reader.open requires a path")
        #expect(missing == expected)
        #expect(blank == expected)
        #expect(actions.calls.isEmpty)
    }

    @Test func openRejectsARelativePathWithoutCallingHost() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderOpen,
                                                                args: ControlArgs(path: "docs/plan.md")))

        #expect(response == ControlResponse(ok: false, error: "reader path must be absolute: docs/plan.md"))
        #expect(actions.calls.isEmpty)
    }

    @Test func openRejectsControlCharactersInThePath() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderOpen,
                                                                args: ControlArgs(path: "/tmp/a\u{1b}b.md")))

        #expect(response == ControlResponse(ok: false, error: "reader path must not contain control characters"))
        #expect(actions.calls.isEmpty)
    }

    @Test func openRejectsAnInvalidPositionAndPercent() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let position = await dispatcher.dispatch(ControlRequest(
            cmd: .sessionReaderOpen, args: ControlArgs(path: "/tmp/a.md", position: "sideways")))
        let percent = await dispatcher.dispatch(ControlRequest(
            cmd: .sessionReaderOpen, args: ControlArgs(sizePercent: 0, path: "/tmp/a.md")))

        #expect(position == ControlResponse(
            ok: false, error: "invalid position: sideways (\(HudPosition.acceptedNamesList))"))
        #expect(percent == ControlResponse(ok: false, error: "session.reader.open: --size-percent must be 1...100"))
        #expect(actions.calls.isEmpty)
    }

    @Test func openForwardsDefaultsWhenOnlyThePathIsGiven() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderOpen, target: "9f3c",
                                                                args: ControlArgs(path: "/repo/plan.md")))

        #expect(response?.ok == true)
        #expect(actions.calls == [.readerOpen(target: "9f3c", window: nil,
                                              ReaderSpec(path: "/repo/plan.md", position: .centerRight,
                                                         sizePercent: 45))])
    }

    @Test func openForwardsAnAliasedPositionAndTheCallersPercent() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)

        let response = await dispatcher.dispatch(ControlRequest(
            cmd: .sessionReaderOpen, args: ControlArgs(sizePercent: 60, window: "w1", path: "/repo/plan.md",
                                                       position: "top")))

        #expect(response?.ok == true)
        #expect(actions.calls == [.readerOpen(target: nil, window: "w1",
                                              ReaderSpec(path: "/repo/plan.md", position: .topCenter,
                                                         sizePercent: 60))])
    }

    @Test func closeForwardsTargetAndWindow() async {
        let actions = MockControlActions()
        actions.nextReaderCloseResponse = ControlResponse(ok: false, error: ReaderError.noReader)
        let dispatcher = ControlDispatcher(actions: actions)

        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionReaderClose, target: "9f3c",
                                                                args: ControlArgs(window: "w1")))

        #expect(response == ControlResponse(ok: false, error: "no reader"))
        #expect(actions.calls == [.readerClose(target: "9f3c", window: "w1")])
    }
}
