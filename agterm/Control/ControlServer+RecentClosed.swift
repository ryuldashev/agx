import Foundation
import agtermCore

/// App-side host for `restore.list` / `restore.open` — the control twin of File ▸ Open Recent. The recent
/// list lives beside the window snapshots rather than inside one, so listing takes no `--window`; a reopen
/// has to land somewhere, so that one does.
///
/// Not to be confused with `restore.clear` (captures) or `session.restore` (pins) in
/// `ControlServer+AppCommands.swift` / `+SessionActions.swift`: three different verbs on one noun.
extension ControlServer {
    func listRecentClosed(limit: Int?) -> ControlResponse {
        let items = library.recentClosedItems
        let nodes = items.enumerated().map { ControlRecentClosedNode.project($0.element, index: $0.offset + 1) }
        return ControlResponse(ok: true, result: ControlResult(closed: Array(nodes.prefix(limit ?? nodes.count))))
    }

    /// Reopen one entry. `target` nil takes the newest, so the CLI's `restore last` needs no argument of its
    /// own. Answers the id of the session the reopen BROUGHT BACK, which is what a caller drives
    /// `session.type` at next — never the store's standing selection, which a workspace entry with no
    /// surviving member leaves untouched and would hand the caller its own live foreground session.
    func openRecentClosed(_ target: String?, window: String?) -> ControlResponse {
        resolver.resolveOpenPlacementStore(window) { store in
            let items = library.recentClosedItems
            guard !items.isEmpty else { return ControlResponse(ok: false, error: "no recently closed items") }
            let resolution = target.map { RecentClosedResolve.resolve($0, items: items) } ?? .resolved(items[0].id)
            guard case .resolved(let id) = resolution else {
                return ControlResponse(ok: false,
                                       error: ControlResolve.errorMessage(noun: "closed item",
                                                                          target: target ?? "last",
                                                                          resolution: resolution))
            }
            guard let item = items.first(where: { $0.id == id }) else {
                return ControlResponse(ok: false, error: ControlResolve.notFoundMessage(noun: "closed item",
                                                                                        target: target ?? "last"))
            }
            guard library.reopenRecentClosed(id, into: store) else {
                return ControlResponse(ok: false, error: "could not reopen \(item.title)")
            }
            if store === library.activeStore { actions.focusActiveSession() }
            return ControlResponse(ok: true, result: ControlResult(id: reopenedSessionID(item, in: store)?.uuidString))
        }
    }

    /// The session a reopen actually produced. A session entry keeps its id, so the snapshot answers
    /// directly. A workspace entry has no id of its own to hand back, so it reports the selection the
    /// rebuild made — but only once that selection is confirmed to live in the rebuilt workspace, since an
    /// entry whose members were all taken restores an EMPTY workspace and selects nothing.
    private func reopenedSessionID(_ item: RecentClosedItem, in store: AppStore) -> UUID? {
        if let session = item.session { return store.session(withID: session.snapshot.id)?.id }
        guard let workspaceID = item.workspace?.snapshot.id,
              let workspace = store.workspaces.first(where: { $0.id == workspaceID }),
              let selected = store.selectedSessionID,
              workspace.sessions.contains(where: { $0.id == selected }) else { return nil }
        return selected
    }
}
