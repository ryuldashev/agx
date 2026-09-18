import AppKit
import Foundation
import agtermCore

/// App-side host for `artifact.*`. The dispatcher normalized the key and validated the text; this layer
/// freezes the showing session's names off the live tree, folds the record into `ArtifactLibrary`, reads
/// the disk for `exists`/`size`, and opens files through `NSWorkspace` exactly as the window's double-click
/// does.
extension ControlServer {
    private var artifacts: ArtifactLibrary? { actions.artifacts }

    func artifactAdd(_ options: ControlArtifactAddOptions) -> ControlResponse {
        guard let artifacts else { return ControlResponse(ok: false, error: "artifact index not started") }
        var sessionID: UUID?
        var sessionName: String?
        var workspaceName: String?
        if let target = options.session {
            // a hook must never fail on a session that closed between the showing and the report: an id the
            // tree no longer holds is recorded bare, only a bad spelling is an error.
            switch resolver.resolveSessionTarget(target, window: nil) {
            case .success(let (store, id)):
                sessionID = id
                sessionName = store.session(withID: id)?.displayName
                workspaceName = store.workspace(forSession: id)?.name
            case .failure(let response):
                guard let id = UUID(uuidString: target) else { return response }
                sessionID = id
            }
        }
        let record = ArtifactRecord(path: options.path, kind: options.kind, title: options.title,
                                    source: options.source, seen: options.seen ?? Date(),
                                    sessionID: sessionID, sessionName: sessionName, workspaceName: workspaceName,
                                    cwd: options.cwd, agentSession: options.agentSession)
        let artifact = artifacts.record(record).artifact
        library.recordControlEvent(ControlEventDraft(
            kind: .artifactAdded, session: sessionID?.uuidString,
            payload: ControlEventPayload(name: artifact.displayName, source: artifact.source.rawValue, path: artifact.path)))
        // no `affected`: a repeat showing is not a failure, and the node's `count` says how many times.
        return ControlResponse(ok: true, result: ControlResult(id: artifact.id.uuidString, artifacts: [Self.node(artifact)]))
    }

    func artifactList(_ options: ControlArtifactListOptions) -> ControlResponse {
        guard let artifacts else { return ControlResponse(ok: false, error: "artifact index not started") }
        var session: UUID?
        if let target = options.session {
            switch resolver.resolveSessionTarget(target, window: nil) {
            case .success(let (_, id)): session = id
            case .failure(let response):
                guard let id = UUID(uuidString: target) else { return response }
                session = id
            }
        }
        var rows = artifacts.index.filtered(query: options.query ?? "", workspace: options.workspace,
                                            category: options.category, session: session,
                                            includeHidden: options.includeHidden)
        if let limit = options.limit { rows = Array(rows.prefix(limit)) }
        return ControlResponse(ok: true, result: ControlResult(artifacts: rows.map(Self.node)))
    }

    func artifactRemove(_ target: String) -> ControlResponse {
        withArtifact(target) { artifacts, item in
            guard let removed = artifacts.remove(id: item.id) else { return Self.noSuchArtifact(target) }
            return ControlResponse(ok: true, result: ControlResult(id: removed.id.uuidString, affected: 1))
        }
    }

    func artifactSetPinned(_ pinned: Bool, target: String) -> ControlResponse {
        withArtifact(target) { artifacts, item in
            guard let updated = artifacts.setPinned(pinned, id: item.id) else { return Self.noSuchArtifact(target) }
            return ControlResponse(ok: true, result: ControlResult(id: updated.id.uuidString, artifacts: [Self.node(updated)]))
        }
    }

    func artifactSetHidden(_ hidden: Bool, target: String) -> ControlResponse {
        withArtifact(target) { artifacts, item in
            guard let updated = artifacts.setHidden(hidden, id: item.id) else { return Self.noSuchArtifact(target) }
            return ControlResponse(ok: true, result: ControlResult(id: updated.id.uuidString, artifacts: [Self.node(updated)]))
        }
    }

    func artifactOpen(_ target: String, reveal: Bool) -> ControlResponse {
        withArtifact(target) { _, item in
            guard ArtifactOpener.open(item, reveal: reveal) else {
                return ControlResponse(ok: false, error: item.kind == .url ? "invalid url: \(item.path)"
                                       : "file not found: \(item.path)")
            }
            return ControlResponse(ok: true, result: ControlResult(id: item.id.uuidString))
        }
    }

    func artifactShow(window: String?) -> ControlResponse {
        guard actions.artifacts != nil else { return ControlResponse(ok: false, error: "artifact index not started") }
        actions.showArtifacts()
        return ControlResponse(ok: true)
    }

    private func withArtifact(_ target: String,
                              _ body: (ArtifactLibrary, agtermCore.Artifact) -> ControlResponse) -> ControlResponse {
        guard let artifacts else { return ControlResponse(ok: false, error: "artifact index not started") }
        guard let item = artifacts.resolve(target) else { return Self.noSuchArtifact(target) }
        return body(artifacts, item)
    }

    private static func noSuchArtifact(_ target: String) -> ControlResponse {
        ControlResponse(ok: false, error: "no such artifact: \(target)")
    }

    static func node(_ item: agtermCore.Artifact) -> ControlArtifactNode {
        let disk = ArtifactOpener.diskState(of: item)
        return ControlArtifactNode.project(item, exists: disk.exists, size: disk.size)
    }
}

/// The one place an artifact meets the filesystem and `NSWorkspace`, shared by the window and the socket.
enum ArtifactOpener {
    /// `exists`/`size` for a file row, both nil for a URL.
    static func diskState(of item: agtermCore.Artifact) -> (exists: Bool?, size: Int?) {
        guard item.kind == .file else { return (nil, nil) }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: item.path) else { return (false, nil) }
        return (true, (attributes[.size] as? NSNumber)?.intValue)
    }

    /// Open in the default app, or select in Finder. False when there is nothing on disk (or no valid URL)
    /// to hand over; the caller reports it.
    @discardableResult
    static func open(_ item: agtermCore.Artifact, reveal: Bool) -> Bool {
        switch item.kind {
        case .url:
            guard let url = URL(string: item.path) else { return false }
            return NSWorkspace.shared.open(url)
        case .file:
            guard FileManager.default.fileExists(atPath: item.path) else { return false }
            let url = URL(fileURLWithPath: item.path)
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return true
            }
            return NSWorkspace.shared.open(url)
        }
    }
}
