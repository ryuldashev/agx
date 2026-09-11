import XCTest

/// The first-launch Welcome panel. Every UI test launches on a fresh isolated state directory, so the
/// panel is suppressed under XCUITest unless `AGTERM_UITEST_SHOW_WELCOME` opts back in, which is what
/// this class does.
@MainActor
final class WelcomeUITests: XCTestCase {
    private var app: XCUIApplication!
    private var stateDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agterm-uitest-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        app?.terminate()
        if let stateDir { try? FileManager.default.removeItem(at: stateDir) }
    }

    private func launch(showWelcome: Bool) {
        app = XCUIApplication()
        app.launchEnvironment["AGTERM_STATE_DIR"] = stateDir.path
        if showWelcome { app.launchEnvironment["AGTERM_UITEST_SHOW_WELCOME"] = "1" }
        app.launchForUITest()
    }

    func testWelcomeShowsOnFirstLaunchAndNotOnTheNextOne() throws {
        launch(showWelcome: true)
        let close = app.buttons["welcome-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "first launch should open the Welcome panel")
        for step in ["notifications", "cli", "hooks", "skill", "agent"] {
            XCTAssertTrue(app.descendants(matching: .any)["welcome-\(step)"].exists, "the \(step) row should be listed")
        }
        XCTAssertTrue(app.descendants(matching: .any)["welcome-move-spawn"].exists, "spawn should be the first move")
        // Close, never a row's Install: that would really install into the running user's config
        close.click()
        XCTAssertTrue(app.staticTexts["session-row"].waitForExistence(timeout: 20),
                      "closing the panel should leave a usable window")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20), "app should quit before the relaunch")

        launch(showWelcome: true)
        XCTAssertTrue(app.staticTexts["session-row"].waitForExistence(timeout: 20), "relaunch should reach the window")
        XCTAssertFalse(app.buttons["welcome-close"].exists, "the panel must not return on a later launch")
    }

    func testWelcomeIsSuppressedForOrdinaryUITestLaunches() throws {
        launch(showWelcome: false)
        XCTAssertTrue(app.staticTexts["session-row"].waitForExistence(timeout: 20), "launch should reach the window")
        XCTAssertFalse(app.buttons["welcome-close"].exists, "a UI test launch without the opt-in must see no panel")
    }
}
