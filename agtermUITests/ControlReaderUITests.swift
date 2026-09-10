import XCTest

/// End-to-end coverage for `session.reader.*` over the real control socket: the reader takes the split's
/// right pane, `tree` reports it through its own `reader` node beside — never instead of — `overlay` and
/// `hud`, and closing gives the split back to whatever it was before.
@MainActor
final class ControlReaderUITests: ControlAPITestCase {
    private var file: URL!

    override func setUp() async throws {
        try await super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("reader-\(UUID().uuidString).md")
        try "# plan\n\n- [ ] first\n".write(to: file, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        _ = try? sendCommand(request(command: "session.reader.close"))
        try? FileManager.default.removeItem(at: file)
        try await super.tearDown()
    }

    func testOpenShowsTheSplitAtTheDefaultWidthAndCloseTakesItDownAgain() throws {
        let session = try activeSessionID()
        XCTAssertEqual(try sessionNode(id: session)["split"] as? Bool, false, "the fixture session starts unsplit")
        let opened = try sendCommand(request(command: "session.reader.open", args: ["path": file.path]))
        XCTAssertEqual(opened["ok"] as? Bool, true, "open should succeed: \(opened)")

        XCTAssertNotNil(pollReader(session, path: file.path), "tree should expose the reader")
        let node = try sessionNode(id: session)
        XCTAssertEqual(node["split"] as? Bool, true, "the reader lives in the split's right pane")
        XCTAssertEqual(node["splitRatio"] as? Double ?? -1, 0.55, accuracy: 0.001, "45% of the width by default")
        XCTAssertEqual(node["overlay"] as? Bool, false, "a reader is not a program overlay")
        XCTAssertNil(node["hud"])

        let closed = try sendCommand(request(command: "session.reader.close", target: session))
        XCTAssertEqual(closed["ok"] as? Bool, true)
        XCTAssertTrue(poll(until: readerNode(session) == nil, timeout: 5), "close should drop the node")
        XCTAssertEqual(try sessionNode(id: session)["split"] as? Bool, false, "a split the reader showed goes with it")

        let again = try sendCommand(request(command: "session.reader.close", target: session))
        XCTAssertEqual(again["ok"] as? Bool, false)
        XCTAssertEqual(again["error"] as? String, "no reader")
    }

    func testASecondOpenReplacesTheFirstAndBoundsTheWidth() throws {
        let session = try activeSessionID()
        _ = try sendCommand(request(command: "session.reader.open", args: ["path": file.path]))
        XCTAssertNotNil(pollReader(session, path: file.path))

        let other = file.deletingLastPathComponent().appendingPathComponent("reader-other-\(UUID().uuidString).md")
        try "# other\n".write(to: other, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: other) }
        let replaced = try sendCommand(request(command: "session.reader.open",
                                               args: ["path": other.path, "sizePercent": 100]))
        XCTAssertEqual(replaced["ok"] as? Bool, true)

        XCTAssertNotNil(pollReader(session, path: other.path), "the second open should replace the first")
        XCTAssertEqual(try sessionNode(id: session)["splitRatio"] as? Double ?? -1, 0.2, accuracy: 0.001,
                       "the width is bounded so the reader never squeezes the shell out")
    }

    func testAMissingFileIsRefusedAndLeavesNoReader() throws {
        let session = try activeSessionID()
        let missing = file.deletingLastPathComponent().appendingPathComponent("absent-\(UUID().uuidString).md")
        let response = try sendCommand(request(command: "session.reader.open", args: ["path": missing.path]))
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "cannot read file: \(missing.path)")
        XCTAssertNil(readerNode(session))
    }

    // MARK: - Helpers

    private func readerNode(_ id: String) -> [String: Any]? {
        (try? sessionNodeIfPresent(id: id))?["reader"] as? [String: Any]
    }

    /// Polls until the session's `reader` node carries `path`, returning it: a replacing open keeps the
    /// slot occupied throughout, so presence alone cannot tell the new panel from the one it replaced.
    private func pollReader(_ id: String, path: String, timeout: TimeInterval = 10) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let reader = readerNode(id), reader["path"] as? String == path { return reader }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return nil
    }

    private func request(command: String, target: String? = nil, args: [String: Any]? = nil) -> String {
        var object: [String: Any] = ["cmd": command]
        if let target { object["target"] = target }
        if let args { object["args"] = args }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
