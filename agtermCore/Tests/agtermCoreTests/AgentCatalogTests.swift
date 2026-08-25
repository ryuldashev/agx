import Foundation
import Testing
@testable import agtermCore

/// Connected-agent shape and the `PATH` probe behind Settings ▸ Agents ▸ Found on This Mac.
struct AgentCatalogTests {

    @Test func blankCommandIsNotRunnable() {
        #expect(AgentDefinition(name: "x", command: "   ").launchCommand == nil)
        #expect(AgentDefinition(name: "x", command: " claude ").launchCommand == "claude")
    }

    @Test func detectFindsOnlyExecutablesOnThePath() {
        let installed: Set<String> = ["/usr/local/bin/claude", "/opt/homebrew/bin/codex"]
        let found = AgentCatalog.detect(searchPath: "/usr/local/bin:/opt/homebrew/bin") { installed.contains($0) }
        #expect(found.map(\.binary) == ["claude", "codex"])
    }

    /// Catalog order, not `PATH` order, so the offered list is stable however the user's `PATH` is arranged.
    @Test func detectionKeepsCatalogOrder() {
        let installed: Set<String> = ["/b/codex", "/a/claude"]
        let found = AgentCatalog.detect(searchPath: "/b:/a") { installed.contains($0) }
        #expect(found.map(\.binary) == ["claude", "codex"])
    }

    @Test func emptyPathFindsNothing() {
        #expect(AgentCatalog.detect(searchPath: "") { _ in true }.isEmpty)
    }

    /// The GUI is launched by launchd, whose `PATH` has none of the per-user tool dirs agents install
    /// into — so the probe must add them rather than trust what it inherited.
    @Test func searchPathAddsPerUserToolDirectories() {
        let path = AgentCatalog.searchPath(environment: ["PATH": "/usr/bin"], home: "/Users/test")
        let dirs = path.split(separator: ":").map(String.init)
        #expect(dirs.contains("/usr/bin"))
        #expect(dirs.contains("/Users/test/.local/bin"))
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(dirs.first == "/usr/bin") // the inherited PATH keeps priority
        #expect(dirs.count == Set(dirs).count) // no duplicate stat targets
    }

    @Test func settingsDropUnrunnableRowsAndResolveByID() {
        let good = AgentDefinition(name: "Claude Code", command: "claude")
        let blankCommand = AgentDefinition(name: "Half typed", command: "")
        let blankName = AgentDefinition(name: " ", command: "codex")
        let settings = AppSettings(agents: [good, blankCommand, blankName])
        #expect(settings.resolvedAgents.map(\.id) == [good.id])
        #expect(settings.agent(withID: good.id)?.command == "claude")
        #expect(settings.agent(withID: blankCommand.id) == nil)
        #expect(settings.agent(withID: nil) == nil)
    }
}
