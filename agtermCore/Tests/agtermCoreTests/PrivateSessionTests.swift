import Foundation
import Testing
@testable import agtermCore

struct PrivateSessionCleanupTests {
    private static func tempRoot() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agx-private-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private static func touch(_ path: String, _ text: String = "x") throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test func targetRejectsAnythingThatIsNotAnID() {
        #expect(PrivateSessionCleanup.Target(agent: .claude, sessionID: "") == nil)
        #expect(PrivateSessionCleanup.Target(agent: .claude, sessionID: "../x") == nil)
        #expect(PrivateSessionCleanup.Target(agent: .claude, sessionID: "a/b") == nil)
        #expect(PrivateSessionCleanup.Target(agent: .claude, sessionID: "5e022a60-8989-4e30-9a00-f8000acb585e") != nil)
        #expect(PrivateSessionCleanup.Target(agent: .codex, sessionID: "019d1c2c-652f-74b1-8dff-adf1ed64984c") != nil)
    }

    @Test func targetIsParsedFromTheHooksRestoreLines() {
        let claude = PrivateSessionCleanup.target(
            fromRestoreCommand: "zsh -lc 'exec claude --resume 5e022a60-8989-4e30-9a00-f8000acb585e --fork-session'")
        #expect(claude == PrivateSessionCleanup.Target(agent: .claude, sessionID: "5e022a60-8989-4e30-9a00-f8000acb585e"))
        let codex = PrivateSessionCleanup.target(fromRestoreCommand: "zsh -lc 'exec codex resume 019d1c2c-652f'")
        #expect(codex == PrivateSessionCleanup.Target(agent: .codex, sessionID: "019d1c2c-652f"))
        #expect(PrivateSessionCleanup.target(fromRestoreCommand: "ssh box") == nil)
        #expect(PrivateSessionCleanup.target(fromRestoreCommand: nil) == nil)
        #expect(PrivateSessionCleanup.target(fromRestoreCommand: "") == nil)
    }

    @Test func historyFilterDropsOnlyTheSessionsLinesAndKeepsMalformedOnes() {
        let text = """
        {"display":"a","sessionId":"one","timestamp":1}
        not json
        {"display":"b","sessionId":"two","timestamp":2}
        {"display":"c","sessionId":"one","timestamp":3}

        """
        let (filtered, dropped) = PrivateSessionCleanup.filterHistory(text, dropping: "one", key: "sessionId")
        #expect(dropped == 2)
        #expect(filtered == """
        not json
        {"display":"b","sessionId":"two","timestamp":2}

        """)
        let untouched = PrivateSessionCleanup.filterHistory(text, dropping: "nine", key: "sessionId")
        #expect(untouched.dropped == 0)
        #expect(untouched.text == text)
    }

    @Test func sweepRemovesExactlyTheSessionsFilesAcrossEveryKnownRoot() throws {
        let home = try Self.tempRoot()
        let tmp = try Self.tempRoot()
        let sid = "5e022a60-8989-4e30-9a00-f8000acb585e"
        let other = "0b18465e-d295-4310-b879-9a155f31a57e"
        let mine = [
            "\(home)/.claude/projects/-Users-rus-me/\(sid).jsonl",
            "\(home)/.claude/projects/-Users-rus-me/\(sid)/subagents/agent-1.jsonl",
            "\(home)/claude-archive/projects/-Users-rus-me/\(sid).jsonl.gz",
            "\(home)/.claude/debug/\(sid).txt",
            "\(home)/.claude/todos/\(sid)-agent-\(sid).json",
            "\(home)/.claude/file-history/\(sid)/abc@v1",
            "\(home)/.claude/session-env/\(sid)/env",
            "\(home)/.claude/tasks/\(sid)/out.txt",
            "\(tmp)/-Users-rus-me/\(sid)/scratchpad/note.md",
        ]
        let theirs = [
            "\(home)/.claude/projects/-Users-rus-me/\(other).jsonl",
            "\(home)/claude-archive/projects/-Users-rus-me/\(other).jsonl.gz",
            "\(home)/.claude/debug/\(other).txt",
            "\(home)/.claude/projects/-Users-rus-me/memory/MEMORY.md",
            "\(tmp)/-Users-rus-me/\(other)/scratchpad/note.md",
        ]
        for path in mine + theirs { try Self.touch(path) }
        try Self.touch("\(home)/.claude/history.jsonl", """
        {"display":"mine","sessionId":"\(sid)"}
        {"display":"theirs","sessionId":"\(other)"}

        """)
        let agxID = UUID()
        try Self.touch("\(home)/.claude/agx-usage/\(agxID.uuidString).json", "{}")

        let target = try #require(PrivateSessionCleanup.Target(agent: .claude, sessionID: sid))
        let report = PrivateSessionCleanup.sweep(.init(id: agxID, targets: [target]),
                                                 roots: .init(home: home, tmp: tmp))

        #expect(report.failed.isEmpty)
        #expect(report.droppedLines == 1)
        for path in mine { #expect(!FileManager.default.fileExists(atPath: path), Comment(rawValue: path)) }
        for path in theirs { #expect(FileManager.default.fileExists(atPath: path), Comment(rawValue: path)) }
        #expect(!FileManager.default.fileExists(atPath: "\(home)/.claude/agx-usage/\(agxID.uuidString).json"))
        let history = try String(contentsOfFile: "\(home)/.claude/history.jsonl", encoding: .utf8)
        #expect(history == "{\"display\":\"theirs\",\"sessionId\":\"\(other)\"}\n")
        #expect(report.summary == "removed 10 files, dropped 1 history line")
        #expect(report.removed.count == 10) // 9 entries (the sid/ dirs count once each) + agx-usage
    }

    @Test func sweepCoversCodexRolloutsAndHistory() throws {
        let home = try Self.tempRoot()
        let sid = "019d1c2c-652f-74b1-8dff-adf1ed64984c"
        let mine = "\(home)/.codex/sessions/2026/03/24/rollout-2026-03-24T00-29-24-\(sid).jsonl"
        let theirs = "\(home)/.codex/sessions/2026/03/24/rollout-2026-03-24T00-30-27-019d1c2d-5af4.jsonl"
        try Self.touch(mine)
        try Self.touch(theirs)
        try Self.touch("\(home)/.codex/history.jsonl", """
        {"session_id":"\(sid)","ts":1,"text":"secret"}
        {"session_id":"019d1c2d-5af4","ts":2,"text":"other"}

        """)
        let target = try #require(PrivateSessionCleanup.Target(agent: .codex, sessionID: sid))
        let report = PrivateSessionCleanup.sweep(.init(id: UUID(), targets: [target]),
                                                 roots: .init(home: home, tmp: home + "/tmp"))
        #expect(report.removed == [mine])
        #expect(report.droppedLines == 1)
        #expect(!FileManager.default.fileExists(atPath: mine))
        #expect(FileManager.default.fileExists(atPath: theirs))
    }

    @Test func sweepWithNothingOnDiskReportsNothing() throws {
        let home = try Self.tempRoot()
        let target = try #require(PrivateSessionCleanup.Target(agent: .claude, sessionID: "abc"))
        let report = PrivateSessionCleanup.sweep(.init(id: UUID(), targets: [target]),
                                                 roots: .init(home: home, tmp: home + "/tmp"))
        #expect(report.isEmpty)
        #expect(report.summary == "nothing left on disk")
    }

    @Test func pendingStoreUpsertsRemovesAndDisappearsWhenEmpty() throws {
        let dir = URL(fileURLWithPath: try Self.tempRoot())
        let store = PrivateCleanupStore(directory: dir)
        #expect(store.load().isEmpty)
        let id = UUID()
        let target = try #require(PrivateSessionCleanup.Target(agent: .claude, sessionID: "abc"))
        store.upsert(.init(id: id, targets: [target], createdAt: Date(timeIntervalSince1970: 1)))
        store.upsert(.init(id: UUID(), targets: [], createdAt: Date(timeIntervalSince1970: 2)))
        #expect(store.load().count == 2)
        #expect(store.load().first { $0.id == id }?.targets == [target])
        let second = try #require(PrivateSessionCleanup.Target(agent: .codex, sessionID: "def"))
        store.upsert(.init(id: id, targets: [target, second], createdAt: Date(timeIntervalSince1970: 1)))
        #expect(store.load().count == 2)
        #expect(store.load().first { $0.id == id }?.targets == [target, second])
        let file = dir.appendingPathComponent("private-cleanup.json").path
        #expect(FileManager.default.fileExists(atPath: file))
        let text = try String(contentsOfFile: file, encoding: .utf8)
        #expect(!text.contains("name"), "the list carries ids only")
        for item in store.load() { store.remove(item.id) }
        #expect(store.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file))
    }
}

@MainActor
struct PrivateSessionStoreTests {
    @Test func privateSessionsNeverReachTheSnapshotOrRecentClosed() throws {
        let (store, recentClosed, persistence) = makeStoreWithRecentClosed()
        let workspace = store.addWorkspace(name: "w")
        let open = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/a"))
        let secret = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/b", isPrivate: true))
        #expect(secret.isPrivate)
        #expect(store.selectedSessionID == secret.id)

        let snapshot = store.snapshot()
        #expect(snapshot.workspaces.flatMap(\.sessions).map(\.id) == [open.id])
        #expect(snapshot.selectedSessionID == nil)
        #expect(snapshot.sessionRecency?.contains(secret.id) != true)
        #expect(persistence.load().workspaces.flatMap(\.sessions).map(\.id) == [open.id])

        store.closeSession(secret.id)
        #expect(recentClosed.load().isEmpty)
        store.closeSession(open.id)
        #expect(recentClosed.load().count == 1)
    }

    @Test func setPrivateTogglesPersistsAndNotifiesTheSink() throws {
        var seen: [UUID] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agterm-tests-\(UUID().uuidString)")
        let persistence = PersistenceStore(directory: dir)
        let store = AppStore(persistence: persistence, privateSessionSink: { seen.append($0.id) })
        let workspace = store.addWorkspace(name: "w")
        let session = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/a"))
        #expect(persistence.load().workspaces.flatMap(\.sessions).count == 1)

        store.setPrivate(true, forSession: session.id)
        #expect(session.isPrivate)
        #expect(persistence.load().workspaces.flatMap(\.sessions).isEmpty)
        store.setPrivate(true, forSession: session.id) // idempotent: no second sink call
        store.setPrivate(false, forSession: session.id)
        #expect(!session.isPrivate)
        #expect(persistence.load().workspaces.flatMap(\.sessions).count == 1)
        #expect(seen == [session.id, session.id])
        store.setPrivate(true, forSession: UUID()) // unknown id: no-op
        #expect(seen.count == 2)
    }

    @Test func restorePinsRecordEveryAgentSessionIDAndTellTheSinkOnlyWhenPrivate() throws {
        var seen = 0
        let store = AppStore(persistence: PersistenceStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("agterm-tests-\(UUID().uuidString)")), privateSessionSink: { _ in seen += 1 })
        let workspace = store.addWorkspace(name: "w")
        let session = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/a"))
        store.setRestoreCommand("zsh -lc 'exec claude --resume aaa --fork-session'", pane: .left, forSession: session.id)
        #expect(session.agentSessionTargets.map(\.sessionID) == ["aaa"])
        #expect(seen == 0)
        store.setPrivate(true, forSession: session.id)
        #expect(seen == 1)
        store.setRestoreCommand("zsh -lc 'exec claude --resume bbb --fork-session'", pane: .left, forSession: session.id)
        store.setRestoreCommand("zsh -lc 'exec claude --resume bbb --fork-session'", pane: .left, forSession: session.id)
        #expect(session.agentSessionTargets.map(\.sessionID) == ["aaa", "bbb"])
        #expect(seen == 2)
        // the split pane's pin is a different program; it never names the main pane's agent.
        store.toggleSplit(session.id)
        store.setRestoreCommand("zsh -lc 'exec claude --resume ccc --fork-session'", pane: .right, forSession: session.id)
        #expect(session.agentSessionTargets.map(\.sessionID) == ["aaa", "bbb"])
    }

    @Test func aRestoredSessionKeepsThePersistedPinAsAnAgentTarget() throws {
        let (store, _, persistence) = makeStoreWithRecentClosed()
        let workspace = store.addWorkspace(name: "w")
        let session = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/a"))
        _ = store.setRestoreCommand("zsh -lc 'exec claude --resume old-id --fork-session'", pane: .left,
                                    forSession: session.id)
        let reloaded = AppStore(persistence: persistence)
        reloaded.restore(from: persistence.load())
        let restored = try #require(reloaded.session(withID: session.id))
        #expect(restored.agentSessionTargets.map(\.sessionID) == ["old-id"])
        _ = reloaded.setRestoreCommand("zsh -lc 'exec claude --resume new-id --fork-session'", pane: .left,
                                       forSession: session.id)
        #expect(restored.agentSessionTargets.map(\.sessionID) == ["old-id", "new-id"])
    }

    @Test func privateSessionIsNeverWrappedDurable() {
        #expect(!DurablePane.shouldWrap(settingOn: true, requested: true, serverExists: true, line: "claude", isPrivate: true))
        #expect(DurablePane.shouldWrap(settingOn: true, requested: false, serverExists: false, line: "claude"))
    }

    @Test func treeReportsPrivateOnlyWhenSet() throws {
        let store = makeStore()
        let workspace = store.addWorkspace(name: "w")
        let open = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/a"))
        let secret = try #require(store.addSession(toWorkspace: workspace.id, cwd: "/tmp/b", isPrivate: true))
        let tree = store.controlTree()
        let nodes = tree.workspaces.flatMap(\.sessions)
        #expect(nodes.first { $0.id == open.id.uuidString }?.private == nil)
        #expect(nodes.first { $0.id == secret.id.uuidString }?.private == true)
        let data = try JSONEncoder().encode(tree)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.components(separatedBy: "\"private\"").count == 2)
    }
}
