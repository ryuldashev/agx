import Foundation

extension ControlDispatcher {
    /// Validates `artifact.*` host-free: the key is normalized here (`ArtifactPolicy.normalize`), the title,
    /// source, category and timestamp are checked, and the host is left with the index, the session lookup
    /// and the disk.
    func dispatchArtifactCommand(_ request: ControlRequest) -> ControlResponse {
        switch request.cmd {
        case .artifactAdd:
            return dispatchArtifactAdd(request)
        case .artifactList:
            return dispatchArtifactList(request)
        case .artifactRemove:
            return withArtifactTarget(request, verb: "artifact.remove") { actions.artifactRemove($0) }
        case .artifactPin:
            let on = request.args?.off != true
            return withArtifactTarget(request, verb: "artifact.pin") { actions.artifactSetPinned(on, target: $0) }
        case .artifactHide:
            let on = request.args?.off != true
            return withArtifactTarget(request, verb: "artifact.hide") { actions.artifactSetHidden(on, target: $0) }
        case .artifactOpen:
            let reveal = request.args?.mode == "reveal"
            if let mode = request.args?.mode, mode != "reveal", mode != "open" {
                return ControlResponse(ok: false, error: "artifact.open: --mode must be open or reveal")
            }
            return withArtifactTarget(request, verb: "artifact.open") { actions.artifactOpen($0, reveal: reveal) }
        case .artifactShow:
            return actions.artifactShow(window: request.args?.window)
        default:
            preconditionFailure("dispatchArtifactCommand called for \(request.cmd.rawValue)")
        }
    }

    private func withArtifactTarget(_ request: ControlRequest, verb: String,
                                    _ body: (String) -> ControlResponse) -> ControlResponse {
        guard let target = request.target.trimmedOrNilValue else {
            return ControlResponse(ok: false, error: "\(verb) requires an artifact id or path")
        }
        return body(target)
    }

    private func dispatchArtifactAdd(_ request: ControlRequest) -> ControlResponse {
        let args = request.args
        guard let raw = args?.path.trimmedOrNilValue else {
            return ControlResponse(ok: false, error: "artifact.add requires a path or URL")
        }
        guard let key = ArtifactPolicy.normalize(raw, cwd: args?.cwd) else {
            return ControlResponse(ok: false, error: "artifact.add: path must be absolute, ~-relative, an http(s) URL, "
                                   + "or relative with --cwd")
        }
        let title = args?.title.trimmedOrNilValue
        if let title, let error = ArtifactPolicy.titleError(title) {
            return ControlResponse(ok: false, error: error)
        }
        var source = ArtifactSource.manual
        if let text = args?.source.trimmedOrNilValue {
            guard let parsed = ArtifactSource(rawValue: text) else {
                return ControlResponse(ok: false, error: "invalid source: \(text) (expected "
                                       + ArtifactSource.allCases.map(\.rawValue).joined(separator: ", ") + ")")
            }
            source = parsed
        }
        var seen: Date?
        if let text = args?.at.trimmedOrNilValue {
            guard let date = Self.parseISO8601(text) else {
                return ControlResponse(ok: false, error: "invalid --seen: \(text) (expected ISO 8601)")
            }
            seen = date
        }
        return actions.artifactAdd(ControlArtifactAddOptions(
            path: key.path, kind: key.kind, title: title, source: source, seen: seen,
            session: request.target.trimmedOrNilValue, cwd: args?.cwd.trimmedOrNilValue,
            agentSession: args?.transcript.trimmedOrNilValue))
    }

    private func dispatchArtifactList(_ request: ControlRequest) -> ControlResponse {
        let args = request.args
        var category: ArtifactCategory?
        if let kinds = args?.kinds, !kinds.isEmpty {
            guard kinds.count == 1, let parsed = ArtifactCategory(rawValue: kinds[0]) else {
                return ControlResponse(ok: false, error: "invalid --kind (expected one of "
                                       + ArtifactCategory.allCases.map(\.rawValue).joined(separator: ", ") + ")")
            }
            category = parsed
        }
        if let limit = args?.limit, limit < 1 {
            return ControlResponse(ok: false, error: "limit must be at least 1")
        }
        return actions.artifactList(ControlArtifactListOptions(
            query: args?.query.trimmedOrNilValue, workspace: args?.workspace.trimmedOrNilValue, category: category,
            session: request.target.trimmedOrNilValue, includeHidden: args?.all == true, limit: args?.limit))
    }

    static func parseISO8601(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
