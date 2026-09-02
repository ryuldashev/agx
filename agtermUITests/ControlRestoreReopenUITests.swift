import XCTest

/// End-to-end coverage for the reopen path: `restore.list` / `restore.open` over the socket, and the
/// title-bar popover's recently-closed section reaching the same entries.
@MainActor
final class ControlRestoreReopenUITests: ControlAPITestCase {
    func testRestoreListStartsEmptyAndRecordsAClose() throws {
        XCTAssertEqual(try closedEntries().count, 0, "a fresh state dir has nothing closed yet")

        let created = try sendCommand(#"{"cmd":"session.new","args":{"name":"gone"}}"#)
        let id = try XCTUnwrap((created["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)

        let entry = try XCTUnwrap(pollClosedEntry(titled: "gone", timeout: 8), "the close should reach restore.list")
        XCTAssertEqual(entry["index"] as? Int, 1, "the newest close is index 1")
        XCTAssertEqual(entry["kind"] as? String, "session")
        XCTAssertEqual(entry["sessionID"] as? String, id, "the entry names the session that closed")
        XCTAssertNil(entry["restoreCommand"], "an unpinned session comes back as a plain shell")
    }

    func testRestoreListReportsThePinnedCommandThatWillRun() throws {
        let created = try sendCommand(#"{"cmd":"session.new","args":{"name":"agent"}}"#)
        let id = try XCTUnwrap((created["result"] as? [String: Any])?["id"] as? String)
        XCTAssertEqual(try sendCommand(#"{"cmd":"session.restore","target":"\#(id)","args":{"mode":"set","command":"echo resumed"}}"#)["ok"] as? Bool,
                       true, "pinning a restore command should succeed")
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)

        let entry = try XCTUnwrap(pollClosedEntry(titled: "agent", timeout: 8))
        XCTAssertEqual(entry["restoreCommand"] as? String, "echo resumed",
                       "the list answers whether reopening brings the program back")
    }

    /// The reopened session keeps its id, so the tree read-back is the proof it came back rather than a
    /// look-alike, and `restore.list` drops the consumed entry.
    func testRestoreOpenByIndexRebuildsTheSessionAndConsumesTheEntry() throws {
        let created = try sendCommand(#"{"cmd":"session.new","args":{"name":"reopenme"}}"#)
        let id = try XCTUnwrap((created["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)
        _ = try XCTUnwrap(pollClosedEntry(titled: "reopenme", timeout: 8))

        let reopened = try sendCommand(#"{"cmd":"restore.open","target":"1"}"#)
        XCTAssertEqual(reopened["ok"] as? Bool, true, "restore.open should succeed, got: \(reopened)")
        XCTAssertEqual((reopened["result"] as? [String: Any])?["id"] as? String, id,
                       "a reopen keeps the session's id")
        XCTAssertNotNil(try sessionNodeIfPresent(id: id), "the reopened session should be back in the tree")
        XCTAssertNil(try pollClosedEntry(titled: "reopenme", timeout: 1), "a consumed entry leaves the list")
    }

    func testRestoreLastReopensTheNewestClose() throws {
        let first = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new","args":{"name":"older"}}"#)["result"] as? [String: Any])?["id"] as? String)
        let second = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new","args":{"name":"newer"}}"#)["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(first)"}"#)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(second)"}"#)
        _ = try XCTUnwrap(pollClosedEntry(titled: "newer", timeout: 8))

        let reopened = try sendCommand(#"{"cmd":"restore.open"}"#)
        XCTAssertEqual((reopened["result"] as? [String: Any])?["id"] as? String, second,
                       "a bare restore.open takes the newest close")
    }

    func testRestoreOpenRejectsAnUnknownTarget() throws {
        let created = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new"}"#)["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(created)"}"#)
        _ = try XCTUnwrap(pollClosedEntry(index: 1, timeout: 8))

        let response = try sendCommand(#"{"cmd":"restore.open","target":"99"}"#)
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "no such closed item: 99")
    }

    func testRestoreOpenWithNothingClosedErrors() throws {
        let response = try sendCommand(#"{"cmd":"restore.open"}"#)
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(response["error"] as? String, "no recently closed items")
    }

    func testRestoreListHonoursTheLimit() throws {
        for name in ["a", "b"] {
            let id = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new","args":{"name":"\#(name)"}}"#)["result"] as? [String: Any])?["id"] as? String)
            _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)
        }
        XCTAssertTrue(poll(until: (try? self.closedEntries().count) == 2, timeout: 8), "both closes should be listed")

        let limited = try sendCommand(#"{"cmd":"restore.list","args":{"limit":1}}"#)
        XCTAssertEqual(((limited["result"] as? [String: Any])?["closed"] as? [[String: Any]])?.count, 1)
    }

    /// A window down to its last session has nothing to switch TO, but may still have something to bring
    /// back — the case that used to leave the clock button dead.
    func testClosedSessionEnablesTheRecentButtonWithNoOtherLiveSession() throws {
        let button = app.buttons["recent-sessions-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        XCTAssertFalse(button.isEnabled, "one session and nothing closed leaves nothing to show")

        let id = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new","args":{"name":"closedone"}}"#)["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)

        XCTAssertTrue(poll(until: button.exists && button.isEnabled, timeout: 8),
                      "a recently closed session should keep the button reachable")
    }

    func testPopoverListsTheClosedSessionUnderItsHeader() throws {
        let id = try XCTUnwrap((try sendCommand(#"{"cmd":"session.new","args":{"name":"popoverclosed"}}"#)["result"] as? [String: Any])?["id"] as? String)
        _ = try sendCommand(#"{"cmd":"session.close","target":"\#(id)"}"#)
        _ = try XCTUnwrap(pollClosedEntry(titled: "popoverclosed", timeout: 8))

        let button = app.buttons["recent-sessions-button"]
        XCTAssertTrue(poll(until: button.exists && button.isEnabled, timeout: 8))
        let row = openPopoverClosedRow(button: button, timeout: 10)
        XCTAssertTrue(row.exists, "the popover should carry a recently-closed row")
        XCTAssertTrue(row.label.contains("popoverclosed"), "got label: \(row.label)")
        XCTAssertTrue(app.staticTexts["recent-closed-header"].exists, "the closed rows sit under their own header")
    }

    // MARK: - helpers

    private func closedEntries() throws -> [[String: Any]] {
        let response = try sendCommand(#"{"cmd":"restore.list"}"#)
        let result = try XCTUnwrap(response["result"] as? [String: Any], "restore.list should carry a result")
        return result["closed"] as? [[String: Any]] ?? []
    }

    private func pollClosedEntry(titled title: String, timeout: TimeInterval) throws -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = (try? closedEntries())?.first(where: { $0["title"] as? String == title }) { return hit }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    private func pollClosedEntry(index: Int, timeout: TimeInterval) throws -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = (try? closedEntries())?.first(where: { $0["index"] as? Int == index }) { return hit }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    /// The popover can dismiss before the first snapshot, so retry the open; a click is only issued while no
    /// row is showing, so it never toggles an already-open popover shut. Mirrors `RecentSessionsButtonUITests`.
    private func openPopoverClosedRow(button: XCUIElement, timeout: TimeInterval) -> XCUIElement {
        let row = app.buttons["recent-closed-row"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if row.exists { return row }
            button.click()
            if row.waitForExistence(timeout: 1) { return row }
        }
        return row
    }
}
