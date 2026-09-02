import Foundation

/// The outcome of resolving a control target string against a candidate id set.
public enum TargetResolution: Equatable, Sendable {
    case resolved(UUID)
    case notFound
    case ambiguous([UUID])
}

/// Pure resolvers shared by the socket server and the CLI so the wire contract cannot drift:
/// turning a target string into an id, and deriving the socket path from the state directory.
public enum ControlResolve {
    /// Resolve a target string against a candidate id set.
    ///
    /// `candidates` are session ids (for session commands) or workspace ids (for workspace commands);
    /// `active` is the currently selected session / current workspace. Matching order:
    /// - empty string → `.notFound` (an empty prefix would otherwise match everything).
    /// - `"active"` → the active id, or `.notFound` when nil.
    /// - exact `uuidString` (case-insensitive) → `.resolved`.
    /// - otherwise a prefix match on `uuidString.lowercased()`: 1 hit → `.resolved`,
    ///   0 → `.notFound`, ≥2 → `.ambiguous(hits)`.
    public static func resolve(_ target: String, candidates: [UUID], active: UUID?) -> TargetResolution {
        guard !target.isEmpty else { return .notFound }

        if target == "active" {
            guard let active else { return .notFound }
            return .resolved(active)
        }

        let needle = target.lowercased()
        if let exact = candidates.first(where: { $0.uuidString.lowercased() == needle }) {
            return .resolved(exact)
        }

        let hits = candidates.filter { $0.uuidString.lowercased().hasPrefix(needle) }
        switch hits.count {
        case 0: return .notFound
        case 1: return .resolved(hits[0])
        default: return .ambiguous(hits)
        }
    }

    /// The ids whose name matches `target` exactly, case-insensitively, in candidate order. Backs the NAME
    /// arm of a selector that also takes ids (`session.new --workspace`): the id matcher runs first and this
    /// only on its clean miss, so a workspace named after another's id prefix can never shadow it.
    public static func idsNamed(_ target: String, candidates: [(id: UUID, name: String)]) -> [UUID] {
        let needle = target.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return candidates.filter { $0.name.lowercased() == needle }.map(\.id)
    }

    /// The canonical ambiguous-NAME control error — the twin of `ambiguousMessage`, which says "prefix" and
    /// would misname a collision between two workspaces that genuinely share a name.
    public static func ambiguousNameMessage(noun: String, target: String, hits: [UUID]) -> String {
        let listed = hits.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
        return "ambiguous \(noun) name '\(target)' → \(listed) (address it by id)"
    }

    /// The canonical not-found control error for a target resolution miss.
    public static func notFoundMessage(noun: String, target: String) -> String {
        "no such \(noun): \(target)"
    }

    /// The canonical ambiguous-prefix control error, listing matching ids by their first 8 characters.
    public static func ambiguousMessage(noun: String, target: String, hits: [UUID]) -> String {
        let listed = hits.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")
        return "ambiguous \(noun) prefix '\(target)' → \(listed)"
    }

    /// The canonical control error for an unresolved target. `.resolved` maps to not-found so callers
    /// that resolve an id but cannot find its owner keep the same wire contract as a normal miss.
    public static func errorMessage(noun: String, target: String, resolution: TargetResolution) -> String {
        guard case .ambiguous(let hits) = resolution else {
            return notFoundMessage(noun: noun, target: target)
        }
        return ambiguousMessage(noun: noun, target: target, hits: hits)
    }

    /// Derive the control socket path. With `stateDir` (the `AGTERM_STATE_DIR` value, if set) it is
    /// `<stateDir>/<Brand.socketFileName>`; otherwise `<appSupport>/<Brand.socketFileName>`. The app and
    /// the CLI both call this with the same inputs, so they always rendezvous on the same path.
    public static func socketPath(stateDir: String?, appSupport: String) -> String {
        let base = stateDir ?? appSupport
        return (base as NSString).appendingPathComponent(Brand.socketFileName)
    }
}
