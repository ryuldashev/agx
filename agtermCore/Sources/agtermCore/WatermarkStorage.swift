import Foundation

/// Host-free on-disk location of rendered `.text` watermark PNGs — a `watermarks/` subdir of the state
/// directory (honoring `AGTERM_STATE_DIR` for test isolation, like the snapshot/settings files). Pure
/// Foundation (no AppKit), so the app-target renderer (`WatermarkRenderer`, which writes the PNGs) and
/// the host-free `AppStore` (which removes a session's PNG when the session is permanently destroyed)
/// share one path definition. Each function takes an optional `stateDir` override (default nil = the
/// `AGTERM_STATE_DIR`/app-support resolution) so tests can inject a temp directory without mutating
/// process-global env (parallel-safe).
public enum WatermarkStorage {
    /// `<stateDir>/watermarks` — NOT created. Use `ensureDirectory()` before writing.
    public static func directoryURL(stateDir: URL? = nil) -> URL {
        let base = stateDir
            ?? ProcessInfo.processInfo.environment["AGTERM_STATE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? PersistenceStore.defaultDirectory
        return base.appendingPathComponent("watermarks", isDirectory: true)
    }

    /// `directoryURL()`, created lazily (best effort). Called before rendering a `.text` PNG.
    @discardableResult
    public static func ensureDirectory(stateDir: URL? = nil) -> URL {
        let dir = directoryURL(stateDir: stateDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The per-session rendered-text PNG path (`<stateDir>/watermarks/<sessionID>.png`).
    public static func renderedTextURL(sessionID: UUID, stateDir: URL? = nil) -> URL {
        directoryURL(stateDir: stateDir).appendingPathComponent("\(sessionID.uuidString).png")
    }

    /// The cached horizontally-flipped copy of `path` (`<stateDir>/watermarks/mirror-<key>.png`), keyed by
    /// the source path and its modification time so an edited source re-renders instead of serving a stale
    /// flip. The key is FNV-1a, NOT `Hasher`, whose per-process random seed would orphan the cache on every
    /// launch; hashed rather than sanitized because an arbitrary file path is not a legal file name.
    public static func mirroredImageURL(sourcePath: String, modified: Date?, stateDir: URL? = nil) -> URL {
        let stamp = String(Int((modified ?? .distantPast).timeIntervalSince1970))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array("\(sourcePath)@\(stamp)".utf8) {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return directoryURL(stateDir: stateDir).appendingPathComponent("mirror-\(String(hash, radix: 36)).png")
    }

    /// Remove a session's rendered `.text` PNG (best effort), so the state dir doesn't accumulate stale
    /// files. A no-op when none exists. Called on watermark clear AND when the owning session is
    /// permanently removed (`AppStore.closeSession`/`removeWorkspace`) — a `.text` watermark always
    /// re-renders its PNG on apply, so an over-eager removal is self-healing.
    public static func removeRenderedText(sessionID: UUID, stateDir: URL? = nil) {
        try? FileManager.default.removeItem(at: renderedTextURL(sessionID: sessionID, stateDir: stateDir))
    }
}
