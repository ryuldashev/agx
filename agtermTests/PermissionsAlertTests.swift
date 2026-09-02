import agtermCore
import XCTest
@testable import agterm

/// The permission wall is built by hand out of checkboxes, Settings buttons and wrapped reason labels, so
/// the layout and the row-to-area mapping are what a hosted test can still catch — a mismatch there would
/// grant the wrong thing.
@MainActor
final class PermissionsAlertTests: XCTestCase {
    func testOneCheckboxPerProbeableArea() {
        let built = PermissionsAlert.makeAlert()
        XCTAssertEqual(built.checkboxes.map(\.title), PermissionPrimer.probeableAreas.map(\.title),
                       "checkbox order must match probeableAreas — present() zips them to pick what to probe")
        XCTAssertTrue(built.checkboxes.allSatisfy { $0.state == .on })
    }

    func testCheckboxesAlignWithTheAlertTextColumn() throws {
        let built = PermissionsAlert.makeAlert()
        let content = try XCTUnwrap(built.alert.window.contentView)
        let title = try XCTUnwrap(firstTextField(in: content, matching: PermissionPrimer.title))
        let titleX = leadingX(of: title, in: content)
        let first = try XCTUnwrap(built.checkboxes.first)
        XCTAssertEqual(leadingX(of: first, in: content), titleX, accuracy: 1,
                       "the first checkbox should start at the text column, not the icon column")
    }

    func testButtonsOfferGrantAttributionAndLater() {
        let built = PermissionsAlert.makeAlert()
        XCTAssertEqual(built.alert.buttons.map(\.title), ["Grant", PermissionPrimer.runningButton, "Later"])
    }

    func testSettingsOnlyAreasGetAButtonNotACheckbox() throws {
        let built = PermissionsAlert.makeAlert()
        let content = try XCTUnwrap(built.alert.accessoryView)
        for area in PermissionPrimer.areas where area.probePath == nil {
            XCTAssertNotNil(button(in: content, identifier: "permission-\(area.id)-settings"),
                            "\(area.id) has no dialog to raise, so it must open System Settings")
        }
    }

    /// The attribution list runs against the live window library; with no windows open it must come back
    /// empty rather than trip over an unrealized surface.
    func testRunningLinesAreEmptyWithoutOpenWindows() throws {
        let stateDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("permissions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stateDir) }
        let library = WindowLibrary(directory: stateDir)
        XCTAssertTrue(PermissionsAlert.runningLines(library: library).isEmpty)
    }

    private func button(in view: NSView, identifier: String) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton, button.accessibilityIdentifier() == identifier { return button }
            if let found = button(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

    private func leadingX(of view: NSView, in content: NSView) -> CGFloat {
        view.convert(NSPoint.zero, to: content).x + view.alignmentRectInsets.left
    }

    private func firstTextField(in view: NSView, matching value: String) -> NSTextField? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.stringValue == value { return field }
            if let found = firstTextField(in: subview, matching: value) { return found }
        }
        return nil
    }
}
