import Foundation
import agtermCore

/// App-side host for `session.autoanswer`. The dispatcher validated the mode; this resolves the session,
/// lets `AutoAnswerCoordinator` apply an `on`/`off`, and answers with the session's effective state.
extension ControlServer {
    func setSessionAutoAnswer(_ target: String?, options: ControlAutoAnswerOptions) -> ControlResponse {
        resolver.resolveSession(target, window: options.window) { store, id in
            guard let session = store.session(withID: id) else {
                return ControlResponse(ok: false, error: "no such session")
            }
            if let enable = options.enable {
                guard let coordinator = actions.autoAnswer else {
                    return ControlResponse(ok: false, error: "auto-answer not started")
                }
                coordinator.setEnabled(enable, session: session, store: store)
            }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString,
                                                                   autoAnswer: store.autoAnswerNode(session)))
        }
    }
}
