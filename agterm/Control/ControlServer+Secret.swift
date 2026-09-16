import Foundation
import agtermCore

/// App-side host for `secret.*`. The dispatcher validated the label and value; this layer is the only place
/// the keychain is touched from the socket, and `secretInsert` reuses `session.type`'s realize-and-inject so
/// the value goes to the pty exactly as typed text would, never into a response.
extension ControlServer {
    func secretList() -> ControlResponse {
        do {
            return ControlResponse(ok: true, result: ControlResult(secrets: try KeychainSecretStore.labels()))
        } catch {
            return ControlResponse(ok: false, error: "keychain: \(error)")
        }
    }

    func secretAdd(label: String, value: String) -> ControlResponse {
        do {
            try KeychainSecretStore.set(value, label: label)
            return ControlResponse(ok: true, result: ControlResult(id: label))
        } catch {
            return ControlResponse(ok: false, error: "keychain: \(error)")
        }
    }

    func secretRemove(label: String) -> ControlResponse {
        do {
            guard try KeychainSecretStore.remove(label: label) else {
                return ControlResponse(ok: false, error: "no such secret: \(label)")
            }
            return ControlResponse(ok: true, result: ControlResult(id: label, affected: 1))
        } catch {
            return ControlResponse(ok: false, error: "keychain: \(error)")
        }
    }

    func secretInsert(label: String, target: String?, window: String?, pane: String?) async -> ControlResponse {
        let value: String
        do {
            guard let stored = try KeychainSecretStore.value(label: label) else {
                return ControlResponse(ok: false, error: "no such secret: \(label)")
            }
            value = stored
        } catch {
            return ControlResponse(ok: false, error: "keychain: \(error)")
        }
        switch resolver.resolveSessionTarget(target, window: window) {
        case .failure(let response):
            return response
        case .success(let (store, id)):
            return await injectText(value, into: id, store: store, select: false, pane: pane)
        }
    }
}
