import Foundation

/// Where the in-app updater stands, as the control API and the menu read it (ADR 0003). The app side
/// (Sparkle) drives the transitions; this module owns the vocabulary and the read-back shape.
public enum AppUpdateState: String, Sendable, Equatable {
    /// Nothing checked yet, or the last check found the running version current.
    case idle
    case checking
    /// A newer version is known; `update.install` (or the menu) fetches and installs it.
    case available
    case downloading
    /// Downloaded and verified; installs on relaunch or on the user's confirmation.
    case ready
    case installing
    case error
}

/// Decides whether the updater runs at all. Host-free so the gate is testable without Sparkle: a build
/// with no real version (a `0.0.0` local build), a Debug build (its bundle lives in DerivedData and has
/// its own bundle id), an isolated or test instance, or an explicit `AGX_NO_UPDATE` opt-out all read as
/// disabled, and a disabled updater is omitted from `tree` rather than reported.
public enum AppUpdatePolicy {
    public static let optOutVariable = "AGX_NO_UPDATE"
    /// A staging feed for trying an update end to end from a local build: its presence lifts every gate
    /// below except the opt-out. The EdDSA check still applies, so it cannot install an unsigned build.
    public static let stagingFeedVariable = "AGX_UPDATE_FEED"

    public static func stagingFeed(environment: [String: String]) -> String? {
        guard let url = environment[stagingFeedVariable], !url.isEmpty else { return nil }
        return url
    }

    public static func isEnabled(version: String?, isDebugBuild: Bool, environment: [String: String]) -> Bool {
        if environment[optOutVariable] == "1" { return false }
        if stagingFeed(environment: environment) != nil { return true }
        guard !isDebugBuild else { return false }
        guard let version, version != "0.0.0", version != "unknown", !version.isEmpty else { return false }
        if environment["AGTERM_STATE_DIR"] != nil { return false }
        if environment["AGTERM_HOSTED_TESTS"] == "1" { return false }
        if environment.keys.contains(where: { $0.hasPrefix("AGTERM_UITEST") }) { return false }
        return true
    }
}

/// The `update` node on the tree top level and the result of `update.*`; omitted when the updater is
/// disabled (see `AppUpdatePolicy`).
public struct ControlUpdateNode: Codable, Sendable, Equatable {
    /// The running `CFBundleShortVersionString`.
    public let version: String
    public let state: String
    /// The newer version found by the last check, present in `available`/`downloading`/`ready`/`installing`.
    public let available: String?
    /// ISO 8601 with the local offset; nil until a check completes in this app run.
    public let lastChecked: String?
    /// Sparkle's scheduled daily check, as the user left it.
    public let automatic: Bool
    public let error: String?

    public init(version: String, state: String, available: String? = nil, lastChecked: String? = nil,
                automatic: Bool, error: String? = nil) {
        self.version = version
        self.state = state
        self.available = available
        self.lastChecked = lastChecked
        self.automatic = automatic
        self.error = error
    }

    /// One line for the CLI: the running version, then what the last check concluded.
    public var humanDescription: String {
        var line = "\(Brand.productName) \(version)"
        switch AppUpdateState(rawValue: state) {
        case .available?, .downloading?, .ready?, .installing?:
            line += " — \(state): \(available ?? "?") available"
            if state == AppUpdateState.available.rawValue { line += " (agtermctl update install)" }
        case .checking?:
            line += " — checking"
        case .error?:
            line += " — error: \(error ?? "unknown")"
        default:
            line += lastChecked == nil ? " — not checked yet" : " — up to date"
        }
        if let lastChecked { line += " (checked \(lastChecked))" }
        if !automatic { line += " [automatic checks off]" }
        return line
    }
}
