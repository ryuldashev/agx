import Foundation
import OSLog
import agtermCore

/// Raises the real macOS dialogs behind `PermissionPrimer`'s probeable rows, and reports what came back.
///
/// macOS has no request API for the file-shaped services — the prompt is a side effect of TOUCHING the
/// data — so the probe is a directory listing and the answer is whether it succeeded. Deliberately off the
/// main thread: the listing blocks until the user answers, and on the main thread that is a frozen app
/// sitting behind a dialog that asks about it.
enum PermissionProbe {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "PermissionProbe")

    /// Probe `areas` in order — one dialog at a time, in the order the wall listed them — and return each
    /// outcome keyed by area id.
    static func request(_ areas: [PermissionPrimer.Area]) async -> [String: PermissionPrimer.Status] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var statuses: [String: PermissionPrimer.Status] = [:]
                for area in areas { statuses[area.id] = probe(area) }
                continuation.resume(returning: statuses)
            }
        }
    }

    /// One area's outcome. A path that does not exist is `absent` and never reaches TCC — nothing is asked
    /// and nothing is recorded, which is why the catalog only probes paths a normal Mac has. A refusal is
    /// indistinguishable from a refusal made months ago (macOS returns the same error and does not re-ask),
    /// so `denied` always means System Settings, never "press Grant again".
    static func probe(_ area: PermissionPrimer.Area) -> PermissionPrimer.Status {
        guard let relative = area.probePath else { return .unknown }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else { return .absent }
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return .granted
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return .denied }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) {
                return .denied
            }
            logger.error("probe \(area.id, privacy: .public) failed: \(error.code, privacy: .public)")
            return .unknown
        }
    }
}
