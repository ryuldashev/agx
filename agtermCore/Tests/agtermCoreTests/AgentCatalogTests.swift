import Foundation
import Testing
@testable import agtermCore

/// Connected-agent shape, the bundled manifests and the `PATH` probe behind Settings ▸ Agents ▸ Found on
/// This Mac.
struct AgentCatalogTests {
    private func agent(_ binary: String) -> AgentProfile {
        AgentCatalog.profile(binary: binary)!
    }

    /// Every `agents/<binary>/agent.json` in the bundled package decodes — the loader skips a malformed one
    /// silently, so this is the check that catches a broken manifest before it ships.
    @Test func everyBundledManifestDecodes() throws {
        let fm = FileManager.default
        let directory = AgentCatalog.sourceDirectory
        let folders = try fm.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".") }
        #expect(AgentCatalog.known.count == folders.count)
        #expect(Set(AgentCatalog.known.map(\.binary)).isSuperset(of: ["claude", "codex", "gemini", "cursor-agent", "opencode", "mimo", "pi"]))
        for folder in folders {
            #expect(fm.fileExists(atPath: directory.appendingPathComponent(folder + "/agent.json").path), "\(folder) has no agent.json")
        }
    }

    /// Manifest folder = binary, so a contributor finds an agent by the command they type.
    @Test func manifestFolderIsNamedAfterTheAgent() throws {
        let folders = try FileManager.default.contentsOfDirectory(atPath: AgentCatalog.sourceDirectory.path)
        for profile in AgentCatalog.known {
            let folder = profile.binary == "cursor-agent" ? "cursor" : profile.binary
            #expect(folders.contains(folder), "no agents/\(folder)/ for \(profile.binary)")
        }
    }

    @Test func catalogOrderComesFromTheManifests() {
        #expect(AgentCatalog.known.prefix(3).map(\.binary) == ["claude", "codex", "gemini"])
        #expect(AgentCatalog.known.last?.binary == "pi")
    }

    @Test func manifestScriptsExistInThePackage() {
        let package = AgentCatalog.sourceDirectory.deletingLastPathComponent()
        for profile in AgentCatalog.known {
            let scripts: [String]
            switch profile.status {
            case .jsonHooks(_, _, let hooks): scripts = hooks.map(\.script)
            case .tomlHooks(_, let script, _): scripts = [script]
            case .plugin(let source, _, _, _): scripts = [source]
            case .none: scripts = []
            }
            for script in scripts {
                #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent(script).path),
                        "\(profile.binary): \(script) missing")
            }
        }
    }

    @Test func malformedManifestIsSkippedNotFatal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("good"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("bad"), withIntermediateDirectories: true)
        try #"{"name": "Good", "binary": "good"}"#.write(to: dir.appendingPathComponent("good/agent.json"), atomically: true, encoding: .utf8)
        try #"{"name": "Bad", "binary": "bad", "status": {"kind": "jsonHooks"}}"#.write(to: dir.appendingPathComponent("bad/agent.json"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AgentCatalog.load(directory: dir).map(\.binary) == ["good"])
        #expect(AgentCatalog.load(directory: nil).isEmpty)
    }

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
        #expect(agent("claude").resumeCommand(sessionID: "ab-12_c") == "claude --resume ab-12_c --fork-session")
        #expect(agent("gemini").resumeCommand(sessionID: "u1") == "gemini -r u1")
        #expect(agent("codex").resumeCommand(sessionID: "t9") == "codex resume t9")
        #expect(agent("claude").resumeCommand(sessionID: "x; rm -rf /") == nil)
        #expect(agent("claude").resumeCommand(sessionID: "") == nil)
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
        #expect(bare.jsonHooksFile == nil)
    }

    @Test func seedArgumentsPlaceTheBriefWhereTheAgentReadsIt() {
        #expect(BriefSeed.positional.arguments(briefArgument: #""$b""#) == #""$b""#)
        #expect(agent("gemini").seed.arguments(briefArgument: #""$b""#) == #"-i "$b""#)
        #expect(agent("opencode").seed.arguments(briefArgument: #""$b""#) == #"--prompt "$b""#)
        #expect(agent("mimo").seed == .flag("--prompt"))
    }

    @Test func geminiHooksMirrorClaudeUnderGeminiEventNames() {
        let events = agent("gemini").jsonHookBindings.map(\.event)
        #expect(events == ["BeforeAgent", "AfterTool", "AfterAgent", "Notification", "SessionStart", "SessionStart"])
        #expect(agent("gemini").jsonHookBindings[3].matcher == "ToolPermission")
        #expect(agent("gemini").jsonHookBindings[4].args == ["--resume-line", "gemini -r {id}"])
        #expect(agent("gemini").jsonHooksFile == ".gemini/settings.json")
        #expect(agent("gemini").jsonHooksDialect == .claude)
    }

    /// Cursor and Mimo are launch + resume only until their hooks are measured in a live pane
    /// (`docs/reference/agents/cursor.md`, `mimo.md`).
    @Test func cursorAndMimoAreLaunchAndResumeOnly() {
        for binary in ["cursor-agent", "mimo"] {
            #expect(agent(binary).supportsResume)
            #expect(!agent(binary).hasStatusIntegration)
            #expect(agent(binary).context == .briefPrefix)
        }
    }

    @Test func claudeKeepsTheStopFailureHook() {
        let claude = agent("claude")
        #expect(claude.jsonHookBindings.last?.event == "StopFailure")
        #expect(claude.jsonHookBindings.last?.script == "agx-agent-failure.sh")
        #expect(claude.context == .sessionStartHook)
        #expect(claude.activate == nil)
    }

    @Test func codexManifestDrivesTheTOMLBlock() {
        guard case .tomlHooks(let file, let script, let events) = agent("codex").status else {
            Issue.record("codex is not tomlHooks"); return
        }
        #expect(file == ".codex/config.toml")
        #expect(script == "agents/codex/status.sh")
        #expect(events.map(\.action) == ["session-start", "user-prompt-submit", "pre-tool-use", "post-tool-use", "permission-request", "stop"])
        #expect(agent("codex").activate?.contains("/hooks") == true)
    }

    @Test func everyKnownBinaryIsUniqueAndProfilesResolveByBinary() {
        let binaries = AgentCatalog.known.map(\.binary)
        #expect(binaries.count == Set(binaries).count)
        #expect(AgentCatalog.profile(binary: "opencode")?.name == "OpenCode")
        #expect(AgentCatalog.profile(binary: "nope") == nil)
    }
}
