import AppKit
import XCTest
@testable import agterm
import agtermCore

/// Hosted coverage for the collapsed-workspace roll-up: a folded workspace row shows its session count and
/// the most attention-worthy session status; an expanded row shows neither.
@MainActor
final class SidebarCollapsedRollupTests: XCTestCase {
    private var stateDir: URL!
    private var library: WindowLibrary!
    private var actions: AppActions!
    private var window: NSWindow!
    private var outline: SidebarOutlineView!
    private var coordinator: WorkspaceSidebar.Coordinator!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            stateDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("agterm-rollup-tests-\(UUID().uuidString)", isDirectory: true)
            library = WindowLibrary(directory: stateDir)
            actions = AppActions(library: library)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            window?.orderOut(nil)
            window = nil
            outline = nil
            coordinator = nil
            actions = nil
            library = nil
            try? FileManager.default.removeItem(at: stateDir)
            stateDir = nil
        }
        try await super.tearDown()
    }

    func testCollapsedWorkspaceShowsCountAndTopStatus() throws {
        let store = try XCTUnwrap(library.activeStore)
        let workspace = try XCTUnwrap(store.workspaces.first)
        let first = try XCTUnwrap(store.activeSession)
        let second = try XCTUnwrap(store.addSession(toWorkspace: workspace.id, cwd: NSHomeDirectory()))
        first.agentIndicator = AgentIndicator(status: .active)
        second.agentIndicator = AgentIndicator(status: .blocked, blink: true)
        buildSidebar(for: store)

        let expandedCell = try renderedWorkspaceCell(workspace.id)
        XCTAssertEqual(expandedCell.sessionCount.count, 0, "an expanded workspace lists its sessions, no count")
        XCTAssertTrue(expandedCell.statusIcon.isHidden, "an expanded workspace carries no status glyph")

        outline.collapseItem(try workspaceNode(workspace.id))
        let collapsedCell = try renderedWorkspaceCell(workspace.id)
        XCTAssertEqual(collapsedCell.sessionCount.count, 2, "a collapsed workspace shows how many sessions it folds")
        XCTAssertFalse(collapsedCell.statusIcon.isHidden, "a collapsed workspace rolls its sessions' status up")
        XCTAssertEqual(collapsedCell.statusIcon.accessibilityValue() as? String, AgentStatus.blocked.rawValue,
                       "blocked outranks active in the roll-up")

        second.agentIndicator = AgentIndicator(status: .idle)
        coordinator.reconcile()
        let afterCell = try renderedWorkspaceCell(workspace.id)
        XCTAssertEqual(afterCell.statusIcon.accessibilityValue() as? String, AgentStatus.active.rawValue,
                       "a status change inside a folded workspace re-renders its roll-up")

        outline.expandItem(try workspaceNode(workspace.id))
        let reopenedCell = try renderedWorkspaceCell(workspace.id)
        XCTAssertEqual(reopenedCell.sessionCount.count, 0, "expanding clears the count again")
        XCTAssertTrue(reopenedCell.statusIcon.isHidden, "expanding clears the roll-up glyph again")
    }

    private func buildSidebar(for store: AppStore) {
        outline = SidebarOutlineView()
        coordinator = WorkspaceSidebar.Coordinator(store: store, actions: actions)
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.headerView = nil
        outline.rowSizeStyle = .custom
        outline.rowHeight = AppSettings.sidebarRowHeight(fontSize: GhosttyApp.shared.sidebarFontSize)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        scroll.documentView = outline
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll

        coordinator.outlineView = outline
        coordinator.renameController.outlineView = outline
        coordinator.seedExpansionFromModel()
        coordinator.reconcile()
    }

    private func workspaceRow(_ id: UUID) throws -> Int {
        outline.layoutSubtreeIfNeeded()
        return try XCTUnwrap((0..<outline.numberOfRows).first { index in
            guard let node = outline.item(atRow: index) as? SidebarNode else { return false }
            return node.kind == .workspace && node.id == id
        }, "the workspace row should be visible in the outline")
    }

    private func workspaceNode(_ id: UUID) throws -> SidebarNode {
        try XCTUnwrap(outline.item(atRow: try workspaceRow(id)) as? SidebarNode)
    }

    private func renderedWorkspaceCell(_ id: UUID) throws -> SidebarCellView {
        let row = try workspaceRow(id)
        return try XCTUnwrap(outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? SidebarCellView)
    }
}
