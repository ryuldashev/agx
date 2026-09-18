import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import agtermCore

/// The Artifacts window: one app-global `NSWindow` hosting `ArtifactsView`, shown by `show_artifacts`
/// (⌘⇧A), Window ▸ Artifacts, the palette row and `artifact.show`. Its own window rather than a deck
/// cover: the list is kept open beside a session and dragged from, and it must not compete with the
/// dashboard or the quick terminal for the overlay slot.
@MainActor
final class ArtifactsWindowController {
    static let shared = ArtifactsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show(library: ArtifactLibrary, actions: AppActions) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = ArtifactsView(library: library, actions: actions)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Artifacts"
        window.contentView = host
        window.minSize = NSSize(width: 640, height: 320)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ArtifactsWindow")
        if window.frame.origin == .zero { window.center() }
        window.setAccessibilityIdentifier("artifacts-window")
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}

/// One table row: the artifact plus what the disk says right now. Built for the FILTERED rows only, so a
/// large index never stats every file per render.
struct ArtifactRow: Identifiable, Equatable {
    let artifact: Artifact
    let exists: Bool
    let size: Int?

    var id: UUID { artifact.id }
    var name: String { artifact.displayName }
    var type: String { artifact.typeLabel }
    var origin: String { [artifact.workspaceName, artifact.sessionName].compactMap { $0 }.joined(separator: " › ") }
    var seen: Date { artifact.lastSeen }
    var sizeValue: Int { size ?? -1 }
    var pinned: Bool { artifact.pinned }

    init(_ artifact: Artifact) {
        self.artifact = artifact
        let disk = ArtifactOpener.diskState(of: artifact)
        exists = disk.exists ?? true
        size = disk.size
    }
}

struct ArtifactsView: View {
    let library: ArtifactLibrary
    let actions: AppActions

    @State private var query = ""
    @State private var workspace: String?
    @State private var category: ArtifactCategory?
    @State private var showHidden = false
    @State private var selection: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<ArtifactRow>] = []
    @State private var quickLookURL: URL?

    private var rows: [ArtifactRow] {
        var rows = library.index.filtered(query: query, workspace: workspace, category: category,
                                          includeHidden: showHidden).map(ArtifactRow.init)
        if !sortOrder.isEmpty { rows.sort(using: sortOrder) }
        return rows
    }

    private var selectedRows: [ArtifactRow] { rows.filter { selection.contains($0.id) } }
    private var primary: ArtifactRow? { selectedRows.first }

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                table
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 320)
        .quickLookPreview($quickLookURL)
    }

    private var filters: some View {
        HStack(spacing: 10) {
            TextField("Search name, path, session…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .accessibilityIdentifier("artifacts-search")
            Picker("Workspace", selection: $workspace) {
                Text("All workspaces").tag(String?.none)
                ForEach(library.index.workspaceNames, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            Picker("Type", selection: $category) {
                Text("All types").tag(ArtifactCategory?.none)
                ForEach(ArtifactCategory.allCases, id: \.self) { kind in
                    Text(kind.title).tag(ArtifactCategory?.some(kind))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 150)
            Spacer()
            Toggle("Show hidden", isOn: $showHidden)
                .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    Image(nsImage: Self.icon(for: row))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(row.name)
                        .lineLimit(1)
                        .foregroundStyle(row.exists ? .primary : .secondary)
                    if row.pinned {
                        Image(systemName: "pin.fill").imageScale(.small).foregroundStyle(.secondary)
                    }
                    if !row.exists {
                        Text("missing").font(.caption).foregroundStyle(.secondary)
                    }
                    if row.artifact.hidden {
                        Text("hidden").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .help(row.artifact.path)
            }
            .width(min: 180, ideal: 300)
            TableColumn("Type", value: \.type) { row in
                Text(row.type).foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 56, max: 90)
            TableColumn("Where", value: \.origin) { row in
                Text(row.origin).lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 260)
            TableColumn("When", value: \.seen) { row in
                Text(Self.relative(row.seen))
                    .foregroundStyle(.secondary)
                    .help(Self.absolute(row.seen))
            }
            .width(min: 80, ideal: 110, max: 160)
            TableColumn("Size", value: \.sizeValue) { row in
                Text(row.size.map(Self.formatSize) ?? "")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 70, max: 100)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            open(ids)
        }
        .onKeyPress(.return) { open(selection); return .handled }
        .onKeyPress(.space) { quickLook(selection); return .handled }
        .onKeyPress(.delete) { hide(selection, true); return .handled }
        .onDeleteCommand { hide(selection, true) }
        .onCopyCommand { copyProviders(selection) }
        .accessibilityIdentifier("artifacts-table")
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<UUID>) -> some View {
        let items = rows.filter { ids.contains($0.id) }
        if items.isEmpty {
            Text("No selection")
        } else {
            Button("Open") { open(ids) }
            Button("Quick Look") { quickLook(ids) }
            Button("Reveal in Finder") { reveal(ids) }
            Button("Copy Path") { copyPaths(ids) }
            Divider()
            if let session = items.first?.artifact.sessionID, actions.library.windowID(forSession: session) != nil {
                Button("Go to Session") { goToSession(session) }
                Divider()
            }
            Button(items.allSatisfy(\.pinned) ? "Unpin" : "Pin") { pin(ids, !items.allSatisfy(\.pinned)) }
            Button(items.allSatisfy(\.artifact.hidden) ? "Unhide" : "Hide") { hide(ids, !items.allSatisfy(\.artifact.hidden)) }
            Divider()
            Button("Remove from List") { remove(ids) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(rows.count == 1 ? "1 artifact" : "\(rows.count) artifacts")
                .foregroundStyle(.secondary)
            if let primary {
                Text(primary.artifact.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Reveal in Finder") { reveal(selection) }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(primary == nil || primary?.artifact.kind == .url)
            Button("Quick Look") { quickLook(selection) }
                .disabled(primary == nil || primary?.artifact.kind == .url)
            Button("Open") { open(selection) }
                .keyboardShortcut(.defaultAction)
                .disabled(primary == nil)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(library.items.isEmpty ? "No artifacts yet" : "Nothing matches")
                .font(.headline)
            Text(library.items.isEmpty
                 ? "An artifact is a file an agent showed you: `open x.pdf`, `agx reader plan.md`, or `agx artifact add`."
                 : "Clear the search or the filters.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: actions

    private func items(_ ids: Set<UUID>) -> [Artifact] {
        rows.filter { ids.contains($0.id) }.map(\.artifact)
    }

    private func open(_ ids: Set<UUID>) {
        for item in items(ids) { ArtifactOpener.open(item, reveal: false) }
        ActionJournal.shared.log("action", ["source": "artifacts", "action": "open", "count": "\(ids.count)"])
    }

    private func reveal(_ ids: Set<UUID>) {
        for item in items(ids) where item.kind == .file { ArtifactOpener.open(item, reveal: true) }
    }

    private func quickLook(_ ids: Set<UUID>) {
        guard let item = items(ids).first(where: { $0.kind == .file }),
              FileManager.default.fileExists(atPath: item.path) else { return }
        quickLookURL = URL(fileURLWithPath: item.path)
    }

    private func copyPaths(_ ids: Set<UUID>) {
        let text = items(ids).map(\.path).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// ⌘C copies the files themselves (Finder-style items) so a paste lands the file in Finder or a chat,
    /// and a URL row copies as text.
    private func copyProviders(_ ids: Set<UUID>) -> [NSItemProvider] {
        items(ids).compactMap { item in
            guard item.kind == .file, FileManager.default.fileExists(atPath: item.path) else {
                return NSItemProvider(object: item.path as NSString)
            }
            return NSItemProvider(contentsOf: URL(fileURLWithPath: item.path))
        }
    }

    private func pin(_ ids: Set<UUID>, _ pinned: Bool) {
        for id in ids { _ = library.setPinned(pinned, id: id) }
    }

    private func hide(_ ids: Set<UUID>, _ hidden: Bool) {
        for id in ids { _ = library.setHidden(hidden, id: id) }
        if hidden, !showHidden { selection.subtract(ids) }
    }

    private func remove(_ ids: Set<UUID>) {
        for id in ids { _ = library.remove(id: id) }
        selection.subtract(ids)
    }

    private func goToSession(_ sessionID: UUID) {
        guard let windowID = actions.library.windowID(forSession: sessionID) else { return }
        actions.reveal(windowID: windowID, sessionID: sessionID, pane: .main)
    }

    // MARK: formatting

    private static func icon(for row: ArtifactRow) -> NSImage {
        switch row.artifact.kind {
        case .url:
            return NSImage(systemSymbolName: "link", accessibilityDescription: "link") ?? NSImage()
        case .file:
            if row.exists { return NSWorkspace.shared.icon(forFile: row.artifact.path) }
            let ext = (row.artifact.path as NSString).pathExtension
            if !ext.isEmpty, let type = UTType(filenameExtension: ext) { return NSWorkspace.shared.icon(for: type) }
            return NSWorkspace.shared.icon(for: .data)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static func absolute(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
