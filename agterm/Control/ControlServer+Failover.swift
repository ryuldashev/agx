import Foundation
import agtermCore

/// App-side host for `session.failure`. The dispatcher validated the text; this resolves the session,
/// classifies the report and lets `AgentFailoverCoordinator` act, answering with the action it took.
extension ControlServer {
    func reportFailure(_ target: String?, options: ControlFailureOptions) -> ControlResponse {
        guard let failover = actions.failover else {
            return ControlResponse(ok: false, error: "agent failover not started")
        }
        return resolver.resolveSession(target, window: options.window) { store, id in
            guard let session = store.session(withID: id) else {
                return ControlResponse(ok: false, error: "no such session")
            }
            let failure = AgentFailure.classify(error: options.error, message: options.message)
            failover.report(failure, session: session, store: store, transcript: options.transcript,
                            forceHandoff: options.forceHandoff)
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString,
                                                                   failover: ControlFailoverNode.project(session.failover)))
        }
    }
}
