import XCTest

/// Insert Secret end to end: `secret.add` stores into the login keychain, Edit ▸ Insert Secret… lists the
/// label, Enter types the value into the terminal, `secret.insert` does the same over the socket, and
/// `secret.remove` takes it back out. The label is unique per run and removed in `tearDown` so a failed run
/// leaves nothing behind in the user's keychain. The ⌥⌘F chord is not driven here: XCUITest's `typeKey`
/// with ⌥ on a letter reaches no menu equivalent in this app (⌥⌘N, a shipped default, is equally inert), so
/// the menu item is the automated entry and the chord is verified by hand.
@MainActor
final class InsertSecretUITests: ControlAPITestCase {
    private let label = "agx-uitest-\(UUID().uuidString.prefix(8))"
    private let value = "s3cr3t-\(Int.random(in: 1000...9999))"

    override func tearDown() async throws {
        _ = try? sendCommand(#"{"cmd":"secret.remove","args":{"label":"\#(label)"}}"#)
        try await super.tearDown()
    }

    func testPaletteListsStoredSecretAndTypesItIntoTheTerminal() throws {
        let id = try activeSessionID()
        let added = try sendCommand(#"{"cmd":"secret.add","args":{"label":"\#(label)","value":"\#(value)"}}"#)
        XCTAssertEqual(added["ok"] as? Bool, true, "secret.add should succeed: \(added)")

        let listed = try sendCommand(#"{"cmd":"secret.list"}"#)
        let labels = (listed["result"] as? [String: Any])?["secrets"] as? [String] ?? []
        XCTAssertTrue(labels.contains(label), "secret.list should carry the new label: \(labels)")

        app.menuBars.menuBarItems["Edit"].click()
        let item = app.menuBars.menuBarItems["Edit"].menus.firstMatch.menuItems["Insert Secret…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Edit menu should offer Insert Secret…")
        item.click()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the secret palette field should appear")
        XCTAssertEqual(field.placeholderValue, "Type a secret into the terminal…")
        let row = app.descendants(matching: .any).matching(identifier: "palette-item-secret-\(label)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the palette should list the stored label")
        app.typeText(String(label.suffix(8)))
        app.typeKey(.return, modifierFlags: [])

        let text = try pollPaneText(target: id, pane: "left", contains: value, attempts: 1, perAttempt: 20) {}
        XCTAssertNotNil(text, "Enter on the row should type the value into the terminal")

        let removed = try sendCommand(#"{"cmd":"secret.remove","args":{"label":"\#(label)"}}"#)
        XCTAssertEqual(removed["ok"] as? Bool, true, "secret.remove should succeed: \(removed)")
        let again = try sendCommand(#"{"cmd":"secret.remove","args":{"label":"\#(label)"}}"#)
        XCTAssertEqual(again["error"] as? String, "no such secret: \(label)")
    }

    func testInsertTypesOverTheSocketWithoutEchoingTheValue() throws {
        let id = try activeSessionID()
        _ = try sendCommand(#"{"cmd":"secret.add","args":{"label":"\#(label)","value":"\#(value)"}}"#)

        let inserted = try sendCommand(#"{"cmd":"secret.insert","target":"\#(id)","args":{"label":"\#(label)"}}"#)
        XCTAssertEqual(inserted["ok"] as? Bool, true, "secret.insert should succeed: \(inserted)")
        XCTAssertNil((inserted["result"] as? [String: Any])?["text"], "the value must never come back over the socket")
        let text = try pollPaneText(target: id, pane: "left", contains: value, attempts: 1, perAttempt: 20) {}
        XCTAssertNotNil(text, "secret.insert should type the value into the target pane")

        let missing = try sendCommand(#"{"cmd":"secret.insert","target":"\#(id)","args":{"label":"no-such-\#(label)"}}"#)
        XCTAssertEqual(missing["error"] as? String, "no such secret: no-such-\(label)")
    }
}
