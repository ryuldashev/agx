import Foundation
import Testing
@testable import agtermCore

/// The per-workspace new-session seed: what it resolves to, what it persists, and how it degrades when
/// the agent it points at is gone.
struct WorkspaceDefaultsTests {
    private let home = "/Users/test"

    // MARK: - resolvedCwd

    @Test func tildeExpandsAgainstHome() {
        #expect(WorkspaceDefaults(cwd: "~/mmee").resolvedCwd(home: home) == "/Users/test/mmee")
        #expect(WorkspaceDefaults(cwd: "~").resolvedCwd(home: home) == "/Users/test")
    }

    @Test func absolutePathPassesThrough() {
        #expect(WorkspaceDefaults(cwd: "/opt/src").resolvedCwd(home: home) == "/opt/src")
    }

    /// A `~name` home-of-another-user path is NOT expanded — it is left verbatim rather than being turned
    /// into a wrong path under this user's home.
    @Test func otherUsersTildeIsLeftAlone() {
        #expect(WorkspaceDefaults(cwd: "~other/src").resolvedCwd(home: home) == "~other/src")
    }

    @Test func blankAndNilBothReadAsUnset() {
        #expect(WorkspaceDefaults(cwd: nil).resolvedCwd(home: home) == nil)
        #expect(WorkspaceDefaults(cwd: "   ").resolvedCwd(home: home) == nil)
    }

    @Test func emptinessIgnoresBlankCwd() {
        #expect(WorkspaceDefaults().isEmpty)
        #expect(WorkspaceDefaults(cwd: " ").isEmpty)
        #expect(!WorkspaceDefaults(cwd: "/tmp").isEmpty)
        #expect(!WorkspaceDefaults(agentID: UUID()).isEmpty)
        #expect(WorkspaceDefaults(cwd: " ").persisted == nil)
    }

    // MARK: - seed precedence

    @Test func explicitRequestBeatsWorkspaceDefault() {
        let defaults = WorkspaceDefaults(cwd: "~/pinned")
        #expect(NewSessionSeed.cwd(requested: "/explicit", defaults: defaults, fallback: "/fallback", home: home)
            == "/explicit")
    }

    @Test func workspaceDefaultBeatsFallback() {
        let defaults = WorkspaceDefaults(cwd: "~/pinned")
        #expect(NewSessionSeed.cwd(requested: nil, defaults: defaults, fallback: "/fallback", home: home)
            == "/Users/test/pinned")
    }

    @Test func fallbackWinsWhenNothingIsPinned() {
        #expect(NewSessionSeed.cwd(requested: nil, defaults: WorkspaceDefaults(), fallback: "/fallback", home: home)
            == "/fallback")
        // a blank request is "no opinion", not an empty cwd
        #expect(NewSessionSeed.cwd(requested: "  ", defaults: WorkspaceDefaults(), fallback: "/fallback", home: home)
            == "/fallback")
    }

    @Test func pinnedAgentBecomesTheCommand() {
        let agent = AgentDefinition(name: "Claude Code", command: "claude")
        let defaults = WorkspaceDefaults(agentID: agent.id)
        #expect(NewSessionSeed.command(requested: nil, defaults: defaults, agents: [agent]) == "claude")
    }

    @Test func explicitCommandBeatsPinnedAgent() {
        let agent = AgentDefinition(name: "Claude Code", command: "claude")
        let defaults = WorkspaceDefaults(agentID: agent.id)
        #expect(NewSessionSeed.command(requested: "htop", defaults: defaults, agents: [agent]) == "htop")
    }

    /// The failure mode that matters: an agent deleted from Settings leaves every workspace pointing at a
    /// dead id. It must open a plain shell, never a stale or empty command line.
    @Test func deletedAgentDegradesToPlainShell() {
        let defaults = WorkspaceDefaults(agentID: UUID())
        #expect(NewSessionSeed.command(requested: nil, defaults: defaults, agents: []) == nil)
    }

    @Test func blankAgentCommandIsNotRun() {
        let agent = AgentDefinition(name: "Half-typed", command: "  ")
        #expect(NewSessionSeed.command(requested: nil, defaults: WorkspaceDefaults(agentID: agent.id),
                                       agents: [agent]) == nil)
    }

    // MARK: - store

    @MainActor
    @Test func storeReadsWritesAndSeeds() {
        let store = makeStore()
        let workspaceID = store.addWorkspace(name: "work").id
        let agent = AgentDefinition(name: "Codex", command: "codex")

        #expect(store.workspaceDefaults(workspaceID).isEmpty)
        #expect(store.setWorkspaceDefaults(WorkspaceDefaults(cwd: "~/mmee", agentID: agent.id),
                                           forWorkspace: workspaceID))
        let seed = store.newSessionSeed(workspaceID: workspaceID, fallbackCwd: "/fallback",
                                        agents: [agent], home: home)
        #expect(seed.cwd == "/Users/test/mmee")
        #expect(seed.command == "codex")
    }

    @MainActor
    @Test func storeRejectsUnknownWorkspaceAndReadsItAsEmpty() {
        let store = makeStore()
        #expect(!store.setWorkspaceDefaults(WorkspaceDefaults(cwd: "/tmp"), forWorkspace: UUID()))
        #expect(store.workspaceDefaults(UUID()).isEmpty)
    }

    // MARK: - persistence

    @MainActor
    @Test func defaultsSurviveASnapshotRoundTrip() {
        let store = makeStore()
        let workspaceID = store.addWorkspace(name: "work").id
        let agentID = UUID()
        store.setWorkspaceDefaults(WorkspaceDefaults(cwd: "~/mmee", agentID: agentID), forWorkspace: workspaceID)

        let restored = makeStore()
        restored.restore(from: store.snapshot())
        #expect(restored.workspaceDefaults(workspaceID).cwd == "~/mmee")
        #expect(restored.workspaceDefaults(workspaceID).agentID == agentID)
    }

    /// A workspace pinning nothing must serialize exactly as it did before the field existed, so a fork
    /// upgrade does not rewrite every user's `workspaces.json`.
    @MainActor
    @Test func untouchedWorkspaceOmitsTheField() throws {
        let store = makeStore()
        store.addWorkspace(name: "work")
        let data = try JSONEncoder().encode(store.snapshot())
        #expect(!String(decoding: data, as: UTF8.self).contains("defaults"))
    }

    /// A hand-edited or future-written `defaults` value must cost that workspace its seed, not its
    /// sessions — the same lossy rule `collapsed` follows.
    @Test func malformedDefaultsDoNotFailTheWorkspace() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"work","sessions":[],"defaults":"nonsense"}
        """
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.name == "work")
        #expect(snapshot.defaults == nil)
    }

    // MARK: - control update shape

    @Test func updateFieldsAreIndependentTriStates() {
        let read = ControlWorkspaceDefaultsUpdate(cwd: nil, agent: nil)
        #expect(read.isRead)
        let clearDir = ControlWorkspaceDefaultsUpdate(cwd: "", agent: nil)
        #expect(!clearDir.isRead)
        #expect(clearDir.cwd.applied(to: "/old") == nil)
        #expect(clearDir.agent == .unchanged)
        let setDir = ControlWorkspaceDefaultsUpdate(cwd: " ~/mmee ", agent: nil)
        #expect(setDir.cwd.applied(to: "/old") == "~/mmee")
    }
}
