import Foundation
import agtermCore

// Private sessions (ADR 0005).
extension AppActions {
    /// ⌘⇧P: the same seed as ⌘N, created private so nothing of it is ever written to disk.
    func newPrivateSession() {
        newSession(isPrivate: true)
    }

    /// Flip a session between private and public, from the row's context item; clean no-op on an unknown id.
    /// Sidebar context menus pass their own store so a background window never routes through the frontmost.
    func togglePrivate(_ sessionID: UUID, in store: AppStore? = nil) {
        guard uiActionsEnabled else { return }
        guard let store = store ?? self.store, let session = store.session(withID: sessionID) else { return }
        store.setPrivate(!session.isPrivate, forSession: sessionID)
    }

    /// The menu bar / palette twin, over the active session. No-op with none selected.
    func togglePrivateActiveSession() {
        guard let id = store?.selectedSessionID else { return }
        togglePrivate(id)
    }
}
