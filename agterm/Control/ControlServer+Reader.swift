import Foundation
import agtermCore

/// App-side host for `session.reader.*`. Validation, error text and response shape stay in
/// `ControlDispatcher+Reader`; this layer supplies what agtermCore cannot — whether the file is there to
/// read, and the live divider, moved the way `session.resize` moves it. The pane itself is `ReaderView`,
/// built by the deck.
extension ControlServer {
    func openReader(_ target: String?, window: String?, spec: ReaderSpec) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            // a missing file is almost always a typo in the agent's path; the watcher would sit on it
            // forever and `tree` would name a document nobody sees.
            guard FileManager.default.isReadableFile(atPath: spec.path) else {
                return ControlResponse(ok: false, error: "\(ReaderError.unreadable): \(spec.path)")
            }
            let session = store.session(withID: id)
            let ratioBefore = session?.splitRatio
            guard store.openReader(id, spec: spec) else {
                return ControlResponse(ok: false, error: "no such session")
            }
            // a freshly shown split seeds its divider from the stored ratio on layout; a split already on
            // screen only moves through the notification `session.resize` posts.
            if let session, session.splitRatio != ratioBefore {
                NotificationCenter.default.post(name: .agtermApplySplitRatio, object: session)
            }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }

    func closeReader(_ target: String?, window: String?) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            guard store.closeReader(id) else {
                return ControlResponse(ok: false, error: ReaderError.noReader)
            }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }
}
