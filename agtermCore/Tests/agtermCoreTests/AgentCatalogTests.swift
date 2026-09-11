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

    @Test func profileIsFoundByTheFirstKnownTokenOfALaunchLine() {
        #expect(AgentCatalog.profile(forCommandLine: #"exec claude "$b""#)?.binary == "claude")
        #expect(AgentCatalog.profile(forCommandLine: "codex --model gpt-5")?.binary == "codex")
        #expect(AgentCatalog.profile(forCommandLine: "zsh -lc 'exec /opt/bin/gemini -i x'")?.binary == "gemini")
        #expect(AgentCatalog.profile(forCommandLine: "vim") == nil)
        #expect(AgentCatalog.profile(forCommandLine: nil) == nil)
        #expect(AgentDefinition(name: "x", command: "cursor-agent").profile?.name == "Cursor Agent")
    }

    @Test func resumeCommandSubstitutesAnIdShapedToken() {
        #expect(AgentCatalog.claude.resumeCommand(sessionID: "ab-12_c") == "claude --resume ab-12_c --fork-session")
        #expect(AgentCatalog.gemini.resumeCommand(sessionID: "u1") == "gemini -r u1")
        #expect(AgentCatalog.codex.resumeCommand(sessionID: "t9") == "codex resume t9")
        #expect(AgentCatalog.claude.resumeCommand(sessionID: "x; rm -rf /") == nil)
        #expect(AgentCatalog.claude.resumeCommand(sessionID: "") == nil)
        #expect(AgentProfile(name: "Aider", binary: "aider").resumeCommand(sessionID: "a") == nil)
    }

    /// A catalog entry with nothing but a name and binary is the graceful floor: launchable, seeded
    /// positionally, no status, no resume, context by brief prefix.
    @Test func bareProfileIsLaunchOnly() {
        let bare = AgentProfile(name: "Crush", binary: "crush")
        #expect(bare.seed == .positional)
        #expect(!bare.supportsResume)
        #expect(!bare.hasStatusIntegration)
        #expect(bare.context == .briefPrefix)
        #expect(bare.jsonHookBindings.isEmpty)
        #expect(bare.jsonHooksSettingsFile == nil)
    }

    @Test func seedArgumentsPlaceTheBriefWhereTheAgentReadsIt() {
        #expect(BriefSeed.positional.arguments(briefArgument: #""$b""#) == #""$b""#)
        #expect(AgentCatalog.gemini.seed.arguments(briefArgument: #""$b""#) == #"-i "$b""#)
        #expect(AgentCatalog.opencode.seed.arguments(briefArgument: #""$b""#) == #"--prompt "$b""#)
        #expect(AgentCatalog.mimo.seed == .flag("--prompt"))
    }

    @Test func geminiHooksMirrorClaudeUnderGeminiEventNames() {
        let events = AgentCatalog.gemini.jsonHookBindings.map(\.event)
        #expect(events == ["BeforeAgent", "AfterTool", "AfterAgent", "Notification", "SessionStart", "SessionStart"])
        #expect(AgentCatalog.gemini.jsonHookBindings[3].matcher == "ToolPermission")
        #expect(AgentCatalog.gemini.jsonHookBindings[4].args.contains("--resume-line 'gemini -r {id}'"))
        #expect(AgentCatalog.gemini.jsonHooksSettingsFile == ".gemini/settings.json")
        #expect(AgentCatalog.gemini.jsonHooksShape == .claude)
    }

    @Test func cursorHooksHaveNoPermissionEventAndAnswerInCursorFormat() {
        let hooks = AgentCatalog.cursor.jsonHookBindings
        #expect(hooks.map(\.event) == ["beforeSubmitPrompt", "postToolUse", "stop", "sessionStart", "sessionStart"])
        #expect(hooks.allSatisfy { $0.matcher == nil })
        #expect(hooks.last?.args == " --format cursor")
        #expect(AgentCatalog.cursor.jsonHooksShape == .cursor)
    }

    @Test func everyKnownBinaryIsUniqueAndProfilesResolveByBinary() {
        let binaries = AgentCatalog.known.map(\.binary)
        #expect(binaries.count == Set(binaries).count)
        #expect(AgentCatalog.profile(binary: "opencode") == AgentCatalog.opencode)
        #expect(AgentCatalog.profile(binary: "nope") == nil)
    }
}
