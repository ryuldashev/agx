import Foundation

extension ControlDispatcher {
    /// `update.*` (ADR 0004) takes no arguments; the app side answers or reports the updater disabled.
    func dispatchUpdateCommand(_ request: ControlRequest) -> ControlResponse {
        switch request.cmd {
        case .updateCheck: return actions.updateCheck()
        case .updateStatus: return actions.updateStatus()
        case .updateInstall: return actions.updateInstall()
        default: return ControlResponse(ok: false, error: "not an update command: \(request.cmd.rawValue)")
        }
    }
}
