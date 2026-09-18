import XCTest

/// End-to-end coverage for `artifact.*` over the real control socket: an add is echoed and listed with the
/// showing session's names frozen in, `artifact.show` puts the Artifacts window on screen with that row,
/// and the row commands (pin, hide, remove) read back through `artifact.list`.
@MainActor
final class ControlArtifactUITests: ControlAPITestCase {
    private var file: URL!

    override func setUp() async throws {
        try await super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4\n".utf8).write(to: file)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file)
        try await super.tearDown()
    }

    func testAddShowsTheRowInTheWindowAndListsItWithTheSessionNames() throws {
        let session = try activeSessionID()
        let added = try sendCommand(request(command: "artifact.add", target: session,
                                            args: ["path": file.path, "title": "Pitch", "source": "open"]))
        XCTAssertEqual(added["ok"] as? Bool, true, "add should succeed: \(added)")
        let result = added["result"] as? [String: Any]
        let id = try XCTUnwrap(result?["id"] as? String)
        let node = try XCTUnwrap((result?["artifacts"] as? [[String: Any]])?.first)
        XCTAssertEqual(node["name"] as? String, "Pitch")
        XCTAssertEqual(node["path"] as? String, file.path)
        XCTAssertEqual(node["exists"] as? Bool, true)
        XCTAssertEqual(node["sessionID"] as? String, session)
        XCTAssertNotNil(node["session"] as? String, "the showing session's name is frozen into the row")
        XCTAssertNotNil(node["workspace"] as? String)

        let shown = try sendCommand(request(command: "artifact.show"))
        XCTAssertEqual(shown["ok"] as? Bool, true)
        let window = app.windows["artifacts-window"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "artifact.show should open the Artifacts window")
        XCTAssertTrue(window.staticTexts["Pitch"].waitForExistence(timeout: 5), "the row should be listed by its title")

        let again = try sendCommand(request(command: "artifact.add", target: session,
                                            args: ["path": file.path, "source": "reader"]))
        XCTAssertEqual((again["result"] as? [String: Any])?["id"] as? String, id, "the same path folds into one row")

        _ = try sendCommand(request(command: "artifact.pin", target: id))
        let hidden = try sendCommand(request(command: "artifact.hide", target: id))
        XCTAssertEqual(hidden["ok"] as? Bool, true)
        let listed = try sendCommand(request(command: "artifact.list", args: ["query": "pitch"]))
        XCTAssertEqual(((listed["result"] as? [String: Any])?["artifacts"] as? [[String: Any]])?.count, 0,
                       "a hidden row is left out by default")
        let all = try sendCommand(request(command: "artifact.list", args: ["query": "pitch", "all": true]))
        let row = try XCTUnwrap(((all["result"] as? [String: Any])?["artifacts"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["count"] as? Int, 2)
        XCTAssertEqual(row["source"] as? String, "reader")
        XCTAssertEqual(row["pinned"] as? Bool, true)
        XCTAssertEqual(row["hidden"] as? Bool, true)

        let removed = try sendCommand(request(command: "artifact.remove", target: String(id.prefix(8))))
        XCTAssertEqual(removed["ok"] as? Bool, true, "a unique id prefix resolves: \(removed)")
        let gone = try sendCommand(request(command: "artifact.open", target: id))
        XCTAssertEqual(gone["ok"] as? Bool, false)
        XCTAssertEqual(gone["error"] as? String, "no such artifact: \(id)")
    }

    func testARelativePathNeedsACwdAndAMissingFileIsListedButNotOpened() throws {
        let refused = try sendCommand(request(command: "artifact.add", args: ["path": "doc/x.pdf"]))
        XCTAssertEqual(refused["ok"] as? Bool, false)
        XCTAssertEqual(refused["error"] as? String,
                       "artifact.add: path must be absolute, ~-relative, an http(s) URL, or relative with --cwd")

        let missing = file.deletingLastPathComponent().appendingPathComponent("absent-\(UUID().uuidString).pdf")
        let added = try sendCommand(request(command: "artifact.add", args: ["path": missing.path]))
        let node = try XCTUnwrap(((added["result"] as? [String: Any])?["artifacts"] as? [[String: Any]])?.first)
        XCTAssertEqual(node["exists"] as? Bool, false)
        XCTAssertNil(node["sessionID"], "no target records no session")
        let id = try XCTUnwrap((added["result"] as? [String: Any])?["id"] as? String)
        let opened = try sendCommand(request(command: "artifact.open", target: id))
        XCTAssertEqual(opened["ok"] as? Bool, false)
        XCTAssertEqual(opened["error"] as? String, "file not found: \(missing.path)")
        _ = try sendCommand(request(command: "artifact.remove", target: id))
    }

    private func request(command: String, target: String? = nil, args: [String: Any]? = nil) -> String {
        var object: [String: Any] = ["cmd": command]
        if let target { object["target"] = target }
        if let args { object["args"] = args }
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
