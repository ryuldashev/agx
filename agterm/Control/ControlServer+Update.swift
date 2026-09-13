import Foundation
import agtermCore

/// App-side host for `update.*` (ADR 0003): every command is a straight call into the updater, which
/// answers the disabled error itself so the three share one wording.
extension ControlServer {
    func updateCheck() -> ControlResponse {
        actions.updater?.checkInBackground() ?? Self.updaterNotStarted
    }

    func updateStatus() -> ControlResponse {
        actions.updater?.status() ?? Self.updaterNotStarted
    }

    func updateInstall() -> ControlResponse {
        actions.updater?.checkForUpdates() ?? Self.updaterNotStarted
    }

    private static let updaterNotStarted = ControlResponse(ok: false, error: "updater not started")
}
