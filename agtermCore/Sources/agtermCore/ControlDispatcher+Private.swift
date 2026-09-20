import Foundation

extension ControlDispatcher {
    /// `session.private` (ADR 0005): parse `on`|`off`|`toggle`; the host computes `toggle` against the session.
    func dispatchSessionPrivate(_ request: ControlRequest) -> ControlResponse {
        guard let mode = ControlToggleMode.parse(request.args?.mode) else {
            return ControlResponse(ok: false, error: "invalid private mode: \(request.args?.mode ?? "toggle")")
        }
        return actions.setSessionPrivate(request.target, window: request.args?.window, mode: mode)
    }
}
