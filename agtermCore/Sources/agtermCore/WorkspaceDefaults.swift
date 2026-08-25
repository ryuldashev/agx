import Foundation

/// What a workspace seeds into every session created inside it: a working directory and an agent to
/// run. Both optional and independent — a workspace can pin only a directory (sessions open there in a
/// plain shell), only an agent (it starts in whatever cwd the global setting resolves), or both.
///
/// Empty is the default and serializes to nothing (`WorkspaceSnapshot.defaults` stays nil), so an
/// untouched tree writes the same `workspaces.json` it always did.
public struct WorkspaceDefaults: Codable, Equatable, Sendable {
    /// The directory new sessions open in, as TYPED — a leading `~` is kept and expanded on read, so a
    /// path stays portable across machines. Nil/blank = fall back to the global new-session setting.
    public var cwd: String?
    /// Which connected agent (`AgentDefinition.id` in `AppSettings.agents`) runs as the session's
    /// process. Nil = a plain shell. A dangling id (the agent was deleted) resolves to nil, never to a
    /// broken command line.
    public var agentID: UUID?
    /// The background composited behind every session started in this workspace (an image file, in
    /// practice) — the workspace's visual identity, so a glance at a window says which project it is. Nil =
    /// the plain theme background. Seeded onto the session at creation, after which the session owns it: a
    /// later `session.background` on one session never rewrites the workspace's default, and changing the
    /// default never restyles sessions that already exist.
    public var background: BackgroundWatermark?

    public init(cwd: String? = nil, agentID: UUID? = nil, background: BackgroundWatermark? = nil) {
        self.cwd = cwd
        self.agentID = agentID
        self.background = background
    }

    /// Whether the workspace pins nothing — the shape that is dropped on save instead of written.
    public var isEmpty: Bool { cwd.trimmedOrNilValue == nil && agentID == nil && background == nil }

    /// The pinned directory as an absolute path (`~` and `~/x` expanded against `home`), nil when unset
    /// or blank. The single read point, so the Settings sheet, `AppActions` and the control server all
    /// resolve one way.
    public func resolvedCwd(home: String) -> String? {
        guard let raw = cwd.trimmedOrNilValue else { return nil }
        if raw == "~" { return home }
        if raw.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(raw.dropFirst(2))) }
        return raw
    }

    /// Nil when empty, self otherwise — how a snapshot stores it, keeping an untouched workspace's JSON
    /// byte-identical to a pre-defaults one.
    public var persisted: WorkspaceDefaults? { isEmpty ? nil : self }
}

/// Resolves what a NEW session actually starts with, folding three sources in a fixed precedence:
/// an explicit request (a `session new --cwd/--command`, a drag-and-drop, the Open Directory panel)
/// beats the workspace's default, which beats the global fallback. Host-free and pure, so the GUI path
/// and the control path cannot drift apart.
public enum NewSessionSeed: Sendable {
    /// The working directory for a new session in `defaults`' workspace. `requested` is what the caller
    /// asked for (nil = "no opinion"); `fallback` is the already-resolved global setting, so this never
    /// needs to know about `NewSessionDirectory`.
    public static func cwd(requested: String?, defaults: WorkspaceDefaults, fallback: String,
                           home: String) -> String {
        if let requested = requested.trimmedOrNilValue { return requested }
        return defaults.resolvedCwd(home: home) ?? fallback
    }

    /// The command a new session runs, nil for a plain shell. `agents` is the connected-agent list the
    /// workspace's `agentID` points into; an id with no match yields nil (a deleted agent degrades to a
    /// shell rather than to a stale command line).
    public static func command(requested: String?, defaults: WorkspaceDefaults,
                               agents: [AgentDefinition]) -> String? {
        if let requested = requested.trimmedOrNilValue { return requested }
        guard let agentID = defaults.agentID else { return nil }
        return agents.first { $0.id == agentID }?.launchCommand
    }
}

extension Optional where Wrapped == String {
    /// `trimmedOrNil` lifted over the optional — nil, blank and whitespace-only all read as "unset",
    /// which is the same rule everywhere a default is stored as an optional string.
    var trimmedOrNilValue: String? { self?.trimmedOrNil }
}

/// A `workspace.defaults` write on the wire, per field: absent leaves it alone, an EMPTY string clears
/// it, anything else sets it. Two independent tri-states, so `--dir X` never disturbs a pinned agent
/// and `--agent ""` never disturbs a pinned directory.
public struct ControlWorkspaceDefaultsUpdate: Sendable, Equatable {
    public enum Field: Sendable, Equatable {
        case unchanged
        case clear
        case set(String)

        /// Wire → field: nil is "not mentioned", blank/whitespace is "clear", the rest sets the trimmed
        /// value. Same blank-is-unset rule the stored defaults use.
        public init(wire: String?) {
            guard let wire else { self = .unchanged; return }
            self = wire.trimmedOrNil.map { Field.set($0) } ?? .clear
        }

        /// Apply to a stored optional: unchanged keeps it, clear nils it, set replaces it.
        public func applied(to current: String?) -> String? {
            switch self {
            case .unchanged: return current
            case .clear: return nil
            case .set(let value): return value
            }
        }
    }

    public var cwd: Field
    public var agent: Field
    /// The background IMAGE path, same tri-state: absent leaves it, empty clears it, a path sets it. Only the
    /// path is addressable on the wire — `opacity`/`fit` ride alongside and apply to whatever path ends up
    /// stored, so `--background-opacity` alone can re-dim an already-pinned image.
    public var backgroundPath: Field
    public var backgroundOpacity: Double?
    public var backgroundFit: BackgroundWatermark.Fit?

    public init(cwd: String?, agent: String?, backgroundPath: String? = nil,
                backgroundOpacity: Double? = nil, backgroundFit: BackgroundWatermark.Fit? = nil) {
        self.cwd = Field(wire: cwd)
        self.agent = Field(wire: agent)
        self.backgroundPath = Field(wire: backgroundPath)
        self.backgroundOpacity = backgroundOpacity
        self.backgroundFit = backgroundFit
    }

    /// Apply the three background inputs to a stored spec: clearing the path drops the whole watermark (an
    /// opacity with no image would be a spec that renders nothing), setting one keeps/creates an `.image`,
    /// and an untouched path lets opacity/fit re-tune the pinned image in place.
    public func appliedBackground(to current: BackgroundWatermark?) -> BackgroundWatermark? {
        var spec: BackgroundWatermark?
        switch backgroundPath {
        case .unchanged: spec = current
        case .clear: return nil
        case .set(let path):
            spec = current.map { var copy = $0; copy.kind = .image; copy.imagePath = path; return copy }
                ?? BackgroundWatermark(kind: .image, imagePath: path)
        }
        guard var resolved = spec else { return nil }
        if let backgroundOpacity { resolved.opacity = backgroundOpacity }
        if let backgroundFit { resolved.fit = backgroundFit }
        return resolved
    }

    /// Whether the call mentions no field — i.e. it is a READ, and must not touch stored state.
    public var isRead: Bool {
        cwd == .unchanged && agent == .unchanged && backgroundPath == .unchanged
            && backgroundOpacity == nil && backgroundFit == nil
    }
}
