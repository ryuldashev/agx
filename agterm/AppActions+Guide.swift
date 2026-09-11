import AppKit
import agtermCore
import Foundation

/// Help ▸ agx Guide. The guide is `docs/guide/` bundled at `Contents/Resources/docs/guide` (see the
/// "Bundle user guide" phase in `project.yml`) and shows in the active session's reader pane, the same path
/// `agx reader` takes, so its chapter links open in place. With no session to host it the file goes to the
/// system's `.md` handler instead of nowhere.
extension AppActions {
    static func bundledGuideURL() -> URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("docs/guide/README.md"),
              FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    func openGuide() {
        guard uiActionsEnabled, let url = Self.bundledGuideURL() else { return }
        guard let store, let id = store.selectedSessionID, let session = store.session(withID: id) else {
            NSWorkspace.shared.open(url)
            return
        }
        let ratioBefore = session.splitRatio
        store.openReader(id, spec: ReaderSpec(path: url.path))
        if session.splitRatio != ratioBefore {
            NotificationCenter.default.post(name: .agtermApplySplitRatio, object: session)
        }
    }
}
