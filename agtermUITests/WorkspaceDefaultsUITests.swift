import XCTest

/// The sidebar's "Workspace Defaults…" sheet, driven for real: the controls have to be on screen and a
/// saved directory has to reach the persisted snapshot.
///
/// This exists because the sheet once shipped with a grouped `Form`, which is scroll-backed and reports
/// no ideal height — inside the sheet's hosting controller it collapsed to nothing and the dialog showed
/// only a title and two buttons. Nothing but a real presentation catches that, so the first test asserts
/// the fields are hittable rather than merely present.
@MainActor
final class WorkspaceDefaultsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var stateDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agterm-uitest-\(UUID().uuidString)", isDirectory: true)
        app = XCUIApplication()
        app.launchEnvironment["AGTERM_STATE_DIR"] = stateDir.path
        app.launchForUITest()
    }

    override func tearDown() async throws {
        app?.terminate()
        if let stateDir { try? FileManager.default.removeItem(at: stateDir) }
    }

    /// Right-clicks the seeded workspace header and picks "Workspace Defaults…".
    private func openSheet() {
        let workspace = app.staticTexts["workspace 1"]
        XCTAssertTrue(workspace.waitForExistence(timeout: 20), "seeded workspace should exist")
        workspace.rightClick()
        let item = app.menuItems["Workspace Defaults…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "context menu should offer Workspace Defaults…")
        item.click()
    }

    /// Polls the persisted snapshot until workspace 1 pins `expected` as its default directory.
    private func pollDefaultCwd(_ expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: stateDir.windowSnapshotFile()),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let workspaces = obj["workspaces"] as? [[String: Any]],
               let workspace = workspaces.first(where: { ($0["name"] as? String) == "workspace 1" }),
               let defaults = workspace["defaults"] as? [String: Any],
               (defaults["cwd"] as? String) == expected {
                return true
            }
            usleep(200_000)
        }
        return false
    }

    func testSheetShowsDirectoryAndAgentControls() throws {
        openSheet()
        XCTAssertTrue(app.textFields["workspace-defaults-dir"].waitForHittable(timeout: 10),
                      "the directory field must be visible — an empty sheet means the layout collapsed")
        XCTAssertTrue(app.buttons["workspace-defaults-choose"].waitForHittable(timeout: 5),
                      "the folder-picker button must be visible")
        XCTAssertTrue(app.popUpButtons["workspace-defaults-agent"].waitForHittable(timeout: 5),
                      "the agent picker must be visible")
    }

    func testSavingPinsTheDirectory() throws {
        openSheet()
        let field = app.textFields["workspace-defaults-dir"]
        XCTAssertTrue(field.waitForHittable(timeout: 10), "the directory field must be reachable to type into")
        field.click()
        field.typeText("/tmp/mmee")
        app.buttons["workspace-defaults-save"].click()
        XCTAssertTrue(pollDefaultCwd("/tmp/mmee", timeout: 10),
                      "Save should persist the typed directory as the workspace default")
    }
}
