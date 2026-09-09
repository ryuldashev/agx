import AppKit
import XCTest
@testable import agterm
import agtermCore

/// Hosted coverage for spring-loaded session activation: a Finder drag dwelling on a session row makes
/// that session current, so a file can be dropped into its pane without a click first.
@MainActor
final class SidebarSpringSelectTests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var actions: AppActions!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("agterm-spring-select-tests-\(UUID().uuidString)", isDirectory: true)
            library = WindowLibrary(directory: stateDir)
            actions = AppActions(library: library)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            actions = nil
            library = nil
            try? FileManager.default.removeItem(at: stateDir)
            stateDir = nil
        }
        try await super.tearDown()
    }

    private struct Fixture {
        let coordinator: WorkspaceSidebar.Coordinator
        let store: AppStore
        let current: UUID
        let other: UUID
    }

    private func makeFixture() throws -> Fixture {
        let store = try XCTUnwrap(library.activeStore)
        let workspace = try XCTUnwrap(store.currentWorkspaceID)
        let other = try XCTUnwrap(store.addSession(toWorkspace: workspace, cwd: NSHomeDirectory())).id
        let current = try XCTUnwrap(store.addSession(toWorkspace: workspace, cwd: NSHomeDirectory())).id
        store.selectSession(current)
        let coordinator = WorkspaceSidebar.Coordinator(store: store, actions: actions)
        coordinator.springLoadDelay = 0.05
        return Fixture(coordinator: coordinator, store: store, current: current, other: other)
    }

    private func wait(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testDwellingOnASessionRowSelectsIt() async throws {
        let f = try makeFixture()

        f.coordinator.scheduleSpringLoadedSelection(over: SidebarNode(kind: .session, id: f.other))
        try await wait(0.15)

        XCTAssertEqual(f.store.selectedSessionID, f.other)
        XCTAssertNil(f.coordinator.pendingSpringLoadedSelection)
    }

    func testLeavingBeforeTheDwellKeepsTheCurrentSession() async throws {
        let f = try makeFixture()

        f.coordinator.scheduleSpringLoadedSelection(over: SidebarNode(kind: .session, id: f.other))
        f.coordinator.finishDraggingSequence()
        try await wait(0.15)

        XCTAssertEqual(f.store.selectedSessionID, f.current)
    }

    func testMovingToAWorkspaceRowCancelsThePendingSelection() throws {
        let f = try makeFixture()
        let workspace = try XCTUnwrap(f.store.currentWorkspaceID)

        f.coordinator.scheduleSpringLoadedSelection(over: SidebarNode(kind: .session, id: f.other))
        XCTAssertEqual(f.coordinator.pendingSpringLoadedSelection?.sessionID, f.other)
        f.coordinator.scheduleSpringLoadedSelection(over: SidebarNode(kind: .workspace, id: workspace))

        XCTAssertNil(f.coordinator.pendingSpringLoadedSelection)
        XCTAssertEqual(f.store.selectedSessionID, f.current)
    }

    func testHoveringTheCurrentSessionSchedulesNothing() throws {
        let f = try makeFixture()

        f.coordinator.scheduleSpringLoadedSelection(over: SidebarNode(kind: .session, id: f.current))

        XCTAssertNil(f.coordinator.pendingSpringLoadedSelection)
    }
}
