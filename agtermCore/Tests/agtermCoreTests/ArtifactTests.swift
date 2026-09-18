import Foundation
import Testing
@testable import agtermCore

struct ArtifactPolicyTests {
    @Test func normalizesPathsAndURLs() {
        #expect(ArtifactPolicy.normalize("/a/b/../c.pdf", cwd: nil)! == ("/a/c.pdf", .file))
        #expect(ArtifactPolicy.normalize(" /a/./c.pdf ", cwd: nil)! == ("/a/c.pdf", .file))
        #expect(ArtifactPolicy.normalize("doc/c.pdf", cwd: "/w")! == ("/w/doc/c.pdf", .file))
        #expect(ArtifactPolicy.normalize("file:///a/c.pdf", cwd: nil)! == ("/a/c.pdf", .file))
        #expect(ArtifactPolicy.normalize("https://x.y/z", cwd: nil)! == ("https://x.y/z", .url))
        #expect(ArtifactPolicy.normalize("HTTP://x.y", cwd: nil)! == ("HTTP://x.y", .url))
        let home = NSHomeDirectory()
        #expect(ArtifactPolicy.normalize("~/c.pdf", cwd: nil)! == (home + "/c.pdf", .file))
    }

    @Test(arguments: [("doc/c.pdf", nil), ("doc/c.pdf", "relative"), ("", "/w"), ("a\tb", "/w"),
                      (String(repeating: "x", count: 4097), "/w")])
    func refusesRelativeWithoutCwdEmptyAndControlCharacters(raw: String, cwd: String?) {
        #expect(ArtifactPolicy.normalize(raw, cwd: cwd) == nil)
    }

    @Test func titleErrorsMatchTheDispatcherWording() {
        #expect(ArtifactPolicy.titleError("Pitch") == nil)
        #expect(ArtifactPolicy.titleError(String(repeating: "a", count: 201)) == "title too long (max 200 characters)")
        #expect(ArtifactPolicy.titleError("a\u{1B}b") == "title must not contain control characters")
    }

    @Test func categoryFollowsTheExtension() {
        func category(_ path: String, kind: ArtifactKind = .file) -> ArtifactCategory {
            Artifact(path: path, kind: kind, firstSeen: .distantPast, lastSeen: .distantPast, source: .open).category
        }
        #expect(category("/a/x.pdf") == .pdf)
        #expect(category("/a/x.PNG") == .image)
        #expect(category("/a/x.md") == .document)
        #expect(category("/a/x.xlsx") == .sheet)
        #expect(category("/a/x.pptx") == .slides)
        #expect(category("/a/x.mp4") == .media)
        #expect(category("/a/x.swift") == .code)
        #expect(category("/a/x.bin") == .other)
        #expect(category("https://x.y", kind: .url) == .url)
    }
}

struct ArtifactIndexTests {
    private let session = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)

    private func showing(_ path: String = "/a/pitch.pdf", seen: Date, source: ArtifactSource = .open,
                         title: String? = nil, session: UUID? = nil, sessionName: String? = nil,
                         workspace: String? = nil) -> ArtifactRecord {
        ArtifactRecord(path: path, kind: .file, title: title, source: source, seen: seen, sessionID: session,
                       sessionName: sessionName, workspaceName: workspace, cwd: nil, agentSession: nil)
    }

    @Test func aRepeatShowingFoldsIntoTheSameRow() {
        var index = ArtifactIndex()
        let first = index.record(showing(seen: t0, session: session, sessionName: "one", workspace: "w1"))
        #expect(first.deduplicated == false)
        let second = index.record(showing(seen: t1, source: .reader, title: "Pitch", sessionName: "two", workspace: "w2"))
        #expect(second.deduplicated)
        #expect(index.items.count == 1)
        let row = index.items[0]
        #expect(row.id == first.artifact.id)
        #expect(row.count == 2)
        #expect(row.firstSeen == t0)
        #expect(row.lastSeen == t1)
        #expect(row.source == .reader)
        #expect(row.title == "Pitch")
        #expect(row.sessionID == nil)
        #expect(row.sessionName == "two")
        #expect(row.workspaceName == "w2")
    }

    @Test func anOlderBackfillNeverOverridesTheLiveRow() {
        var index = ArtifactIndex()
        index.record(showing(seen: t1, session: session, sessionName: "live", workspace: "w"))
        index.setHidden(true, id: index.items[0].id)
        index.record(showing(seen: t0, source: .backfill, title: "Old", sessionName: "old"))
        let row = index.items[0]
        #expect(row.count == 2)
        #expect(row.lastSeen == t1)
        #expect(row.source == .open)
        #expect(row.sessionName == "live")
        #expect(row.title == "Old")
        #expect(row.hidden)
    }

    @Test func aFreshShowingUnhidesButABackfillDoesNot() {
        var index = ArtifactIndex()
        index.record(showing(seen: t0))
        let id = index.items[0].id
        index.setHidden(true, id: id)
        index.record(showing(seen: t1, source: .backfill))
        #expect(index.items[0].hidden)
        index.record(showing(seen: t1, source: .sendfile))
        #expect(!index.items[0].hidden)
    }

    @Test func resolvesByIDPathAndUniquePrefix() {
        var index = ArtifactIndex()
        let a = index.record(showing("/a/one.pdf", seen: t0)).artifact
        let b = index.record(showing("/a/two.pdf", seen: t0)).artifact
        #expect(index.resolve(a.id.uuidString) == a)
        #expect(index.resolve(" /a/two.pdf ") == b)
        #expect(index.resolve(String(a.id.uuidString.prefix(8)).lowercased()) == a)
        #expect(index.resolve("") == nil)
        #expect(index.resolve("/a/three.pdf") == nil)
        let shared = String(a.id.uuidString.prefix(1))
        if b.id.uuidString.hasPrefix(shared) { #expect(index.resolve(shared) == nil) }
    }

    @Test func filteredIsPinnedFirstThenNewestAndMatchesEveryTerm() {
        var index = ArtifactIndex()
        let old = index.record(showing("/a/old.pdf", seen: t0, sessionName: "Оценка v2", workspace: "mars")).artifact
        let new = index.record(showing("/a/new.png", seen: t1, sessionName: "Roblox", workspace: "roblox")).artifact
        let hidden = index.record(showing("/a/hidden.md", seen: t1)).artifact
        index.setHidden(true, id: hidden.id)
        #expect(index.filtered().map(\.id) == [new.id, old.id])
        index.setPinned(true, id: old.id)
        #expect(index.filtered().map(\.id) == [old.id, new.id])
        #expect(index.filtered(includeHidden: true).map(\.id) == [old.id, new.id, hidden.id])
        #expect(index.filtered(query: "оценка OLD").map(\.id) == [old.id])
        #expect(index.filtered(query: "оценка roblox").isEmpty)
        #expect(index.filtered(workspace: "MARS").map(\.id) == [old.id])
        #expect(index.filtered(category: .image).map(\.id) == [new.id])
        #expect(index.workspaceNames == ["mars", "roblox"])
    }

    @Test func filtersBySession() {
        var index = ArtifactIndex()
        let mine = index.record(showing("/a/mine.pdf", seen: t0, session: session)).artifact
        index.record(showing("/a/other.pdf", seen: t1, session: UUID()))
        #expect(index.filtered(session: session).map(\.id) == [mine.id])
    }

    @Test func pruneDropsHiddenThenOldestButNeverPinned() {
        var index = ArtifactIndex()
        for i in 0..<ArtifactPolicy.maxItems {
            index.record(showing("/a/\(i).pdf", seen: t0.addingTimeInterval(Double(i))))
        }
        let oldest = index.items[0].id
        let pinned = index.items[1].id
        let hidden = index.items[5].id
        index.setPinned(true, id: pinned)
        index.setHidden(true, id: hidden)
        index.record(showing("/a/extra1.pdf", seen: t1))
        #expect(index.items.count == ArtifactPolicy.maxItems)
        #expect(index.item(withID: hidden) == nil)
        #expect(index.item(withID: oldest) != nil)
        index.record(showing("/a/extra2.pdf", seen: t1))
        #expect(index.item(withID: oldest) == nil)
        #expect(index.item(withID: pinned) != nil)
    }

    @Test func removeReturnsTheRowOnce() {
        var index = ArtifactIndex()
        let row = index.record(showing(seen: t0)).artifact
        #expect(index.remove(id: row.id) == row)
        #expect(index.remove(id: row.id) == nil)
        #expect(index.items.isEmpty)
    }
}

struct ArtifactStoreTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("artifacts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func roundTripsThroughDisk() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ArtifactStore(directory: directory)
        #expect(store.load().isEmpty)
        var index = ArtifactIndex()
        index.record(ArtifactRecord(path: "/a/pitch.pdf", kind: .file, title: "Pitch", source: .open,
                                    seen: Date(timeIntervalSince1970: 1_700_000_000), sessionID: UUID(),
                                    sessionName: "Оценка", workspaceName: "mars", cwd: "/w", agentSession: "abc"))
        try store.save(index.items)
        #expect(store.load() == index.items)
    }

    @Test func aForeignVersionReadsAsEmpty() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"version": 99, "items": [{"bogus": true}]}"#.utf8)
            .write(to: directory.appendingPathComponent("artifacts.json"))
        #expect(ArtifactStore(directory: directory).load().isEmpty)
    }

    @Test @MainActor func libraryPersistsEveryMutation() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ArtifactLibrary(directory: directory)
        let row = library.record(ArtifactRecord(path: "/a/pitch.pdf", kind: .file, source: .open, seen: Date())).artifact
        library.setPinned(true, id: row.id)
        #expect(ArtifactStore(directory: directory).load().map(\.pinned) == [true])
        library.setHidden(true, id: row.id)
        #expect(ArtifactStore(directory: directory).load().map(\.hidden) == [true])
        #expect(library.resolve("/a/pitch.pdf")?.id == row.id)
        library.remove(id: row.id)
        #expect(ArtifactStore(directory: directory).load().isEmpty)
        #expect(library.items.isEmpty)
    }

    @Test @MainActor func reloadPicksUpAnotherWriter() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = ArtifactLibrary(directory: directory)
        var index = ArtifactIndex()
        index.record(ArtifactRecord(path: "/a/x.pdf", kind: .file, source: .backfill,
                                    seen: Date(timeIntervalSince1970: 1_700_000_000)))
        try ArtifactStore(directory: directory).save(index.items)
        #expect(library.items.isEmpty)
        library.reload()
        #expect(library.items == index.items)
    }
}

struct ControlArtifactNodeTests {
    @Test func projectsTheRowWithDiskState() {
        let seen = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let row = Artifact(id: id, path: "/a/pitch.pdf", kind: .file, title: nil, firstSeen: seen, lastSeen: seen,
                           count: 2, source: .open, sessionID: id, sessionName: "Оценка", workspaceName: "mars",
                           cwd: "/w", agentSession: "abc", pinned: true, hidden: false)
        let node = ControlArtifactNode.project(row, exists: true, size: 42)
        #expect(node.id == id.uuidString)
        #expect(node.name == "pitch.pdf")
        #expect(node.type == "pdf")
        #expect(node.category == "pdf")
        #expect(node.count == 2)
        #expect(node.exists == true)
        #expect(node.size == 42)
        #expect(node.pinned)
        #expect(node.sessionID == id.uuidString)
        #expect(node.session == "Оценка")
        #expect(node.workspace == "mars")
    }
}
