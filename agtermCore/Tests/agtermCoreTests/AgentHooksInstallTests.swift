import Foundation
import Testing
@testable import agtermCore

struct AgentHooksInstallTests {
    private let scriptDir = "/Users/me/.config/agterm/agent-status"

    private func agent(_ binary: String) -> AgentProfile {
        AgentCatalog.profile(binary: binary)!
    }

    /// The Claude Code merge: the claude manifest's bindings into `~/.claude/settings.json`.
    private func mergeClaudeSettings(existing: String?, scriptDir: String) throws -> (json: String, changed: Bool) {
        try AgentHooksInstall.mergeJSONHooks(existing: existing, scriptDir: scriptDir, bindings: agent("claude").jsonHookBindings)
    }

    /// The Codex merge: the codex manifest's adapter and events into `~/.codex/config.toml`.
    private func mergeCodexConfig(existing: String, scriptDir: String) -> AgentHooksInstall.TOMLMergeOutcome {
        guard case .tomlHooks(_, let script, let events) = agent("codex").status else { fatalError("codex is not tomlHooks") }
        return AgentHooksInstall.mergeTOMLHooks(existing: existing, scriptDir: scriptDir, script: script, events: events)
    }

    private func codexHooksBlock(scriptDir: String) -> String {
        guard case .tomlHooks(_, let script, let events) = agent("codex").status else { fatalError("codex is not tomlHooks") }
        return AgentHooksInstall.tomlHooksBlock(scriptDir: scriptDir, script: script, events: events)
    }

    private let codexAdapter = "agents/codex/status.sh"

    private func object(_ json: String) -> [String: Any] {
        let data = json.data(using: .utf8)!
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func events(_ json: String) -> [String: [[String: Any]]] {
        let hooks = object(json)["hooks"] as? [String: Any] ?? [:]
        var out: [String: [[String: Any]]] = [:]
        for (event, value) in hooks {
            out[event] = value as? [[String: Any]] ?? []
        }
        return out
    }

    private func command(_ entry: [String: Any]) -> String? {
        (entry["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }

    @Test func mergeWhenAbsentAddsAllFourHooks() throws {
        let result = try mergeClaudeSettings(existing: nil, scriptDir: scriptDir)
        #expect(result.changed)
        let evts = events(result.json)
        #expect(evts["UserPromptSubmit"]?.count == 1)
        #expect(evts["PostToolUse"]?.count == 2)
        #expect(evts["Stop"]?.count == 1)
        #expect(evts["Notification"]?.count == 1)
        #expect(command(evts["UserPromptSubmit"]![0])?.hasSuffix("agent-status.sh' active --blink") == true)
        // PostToolUse re-asserts active after every tool, clearing a lingering blocked on resume
        #expect(command(evts["PostToolUse"]![0])?.hasSuffix("agent-status.sh' active --blink") == true)
        // only the Stop hook passes --auto-reset (clear-on-visit); active/blocked stay keep-state
        #expect(command(evts["Stop"]![0])?.hasSuffix("agent-status.sh' completed --auto-reset") == true)
        #expect(command(evts["Notification"]![0])?.hasSuffix("agent-status.sh' blocked") == true)
        #expect(command(evts["UserPromptSubmit"]![0])?.contains("--auto-reset") == false)
        #expect(command(evts["Notification"]![0])?.contains("--auto-reset") == false)
        #expect(evts["Notification"]![0]["matcher"] as? String == "permission_prompt")
        #expect(evts["UserPromptSubmit"]![0]["matcher"] == nil)
        #expect(evts["PostToolUse"]![0]["matcher"] == nil)
        // the failure report takes no state argument: the app classifies the error itself
        #expect(evts["StopFailure"]?.count == 1)
        #expect(command(evts["StopFailure"]![0]) == "'\(scriptDir)/agx-agent-failure.sh'")
        #expect(evts["StopFailure"]![0]["matcher"] == nil)
        // the artifact hook fires only for the two tools that show files
        #expect(command(evts["PostToolUse"]![1]) == "'\(scriptDir)/agx-artifacts.sh'")
        #expect(evts["PostToolUse"]![1]["matcher"] as? String == "Bash|SendUserFile")
    }

    /// An older install wrote the SessionStart hooks without arguments; the probe is by script path, so
    /// a re-run neither duplicates them nor rewrites them (the scripts default to Claude's lines).
    @Test func legacyArgumentlessSessionStartHooksAreKept() throws {
        let existing = """
        {"hooks": {"SessionStart": [
          {"hooks": [{"type": "command", "command": "'\(scriptDir)/agx-session-restore.sh'"}]},
          {"hooks": [{"type": "command", "command": "'\(scriptDir)/agx-session-context.sh'"}]}
        ]}}
        """
        let result = try mergeClaudeSettings(existing: existing, scriptDir: scriptDir)
        let starts = events(result.json)["SessionStart"]!
        #expect(starts.count == 2)
        #expect(command(starts[0]) == "'\(scriptDir)/agx-session-restore.sh'")
    }

    @Test func geminiMergeUsesGeminiEventsInTheClaudeShape() throws {
        let result = try AgentHooksInstall.mergeJSONHooks(existing: nil, scriptDir: scriptDir,
                                                          bindings: agent("gemini").jsonHookBindings)
        let evts = events(result.json)
        #expect(command(evts["BeforeAgent"]![0])?.hasSuffix("agent-status.sh' active --blink") == true)
        #expect(command(evts["AfterAgent"]![0])?.hasSuffix("agent-status.sh' completed --auto-reset") == true)
        #expect(evts["Notification"]![0]["matcher"] as? String == "ToolPermission")
        #expect(evts["Stop"] == nil)
        #expect(evts["StopFailure"] == nil)
        #expect(command(evts["SessionStart"]![0])?.contains("--resume-line 'gemini -r {id}'") == true)
        let again = try AgentHooksInstall.mergeJSONHooks(existing: result.json, scriptDir: scriptDir,
                                                         bindings: agent("gemini").jsonHookBindings)
        #expect(!again.changed)
    }

    /// Cursor's dialect, exercised with hand-built bindings: no manifest uses it yet (Cursor ships
    /// launch + resume only until its hooks are measured in a live pane).
    private let cursorBindings = [
        HookBinding(event: "beforeSubmitPrompt", script: AgentHooksInstall.wrapperName, args: ["active", "--blink"]),
        HookBinding(event: "stop", script: AgentHooksInstall.wrapperName, args: ["completed", "--auto-reset"]),
        HookBinding(event: "sessionStart", script: "agx-session-restore.sh", args: ["--resume-line", "cursor-agent --resume {id}"]),
        HookBinding(event: "sessionStart", script: "agx-session-context.sh", args: ["--format", "cursor"]),
    ]

    @Test func cursorMergeWritesFlatRowsUnderVersionOne() throws {
        let existing = """
        {"version": 1, "hooks": {"afterFileEdit": [{"command": "./mine.sh"}]}}
        """
        let result = try AgentHooksInstall.mergeJSONHooks(existing: existing, scriptDir: scriptDir, dialect: .cursor,
                                                          bindings: cursorBindings)
        #expect(result.changed)
        let root = try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
        #expect(root["version"] as? Int == 1)
        let evts = try #require(root["hooks"] as? [String: [[String: Any]]])
        #expect(evts["afterFileEdit"]?.first?["command"] as? String == "./mine.sh")
        #expect(evts["beforeSubmitPrompt"]?.first?["command"] as? String == "'\(scriptDir)/agterm-agent-status.sh' active --blink")
        #expect(evts["stop"]?.first?["command"] as? String == "'\(scriptDir)/agterm-agent-status.sh' completed --auto-reset")
        #expect(evts["beforeSubmitPrompt"]?.first?["hooks"] == nil)
        #expect(evts["sessionStart"]?.count == 2)
        #expect(evts["sessionStart"]?[0]["command"] as? String == "'\(scriptDir)/agx-session-restore.sh' --resume-line 'cursor-agent --resume {id}'")
        #expect(evts["sessionStart"]?[1]["command"] as? String == "'\(scriptDir)/agx-session-context.sh' --format cursor")
        let again = try AgentHooksInstall.mergeJSONHooks(existing: result.json, scriptDir: scriptDir, dialect: .cursor,
                                                         bindings: cursorBindings)
        #expect(!again.changed)
    }

    @Test func cursorMergeIntoAnEmptyFileAddsVersion() throws {
        let result = try AgentHooksInstall.mergeJSONHooks(existing: nil, scriptDir: scriptDir, dialect: .cursor,
                                                          bindings: cursorBindings)
        let root = try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
        #expect(root["version"] as? Int == 1)
    }

    @Test func mergeWhenPresentIsNoOp() throws {
        let first = try mergeClaudeSettings(existing: nil, scriptDir: scriptDir)
        let second = try mergeClaudeSettings(existing: first.json, scriptDir: scriptDir)
        #expect(!second.changed)
        #expect(second.json == first.json)
    }

    @Test func mergePreservesUnrelatedHooksAndKeys() throws {
        let existing = """
        {
          "model": "opus",
          "hooks": {
            "UserPromptSubmit": [
              {"hooks": [{"type": "command", "command": "/usr/bin/other-hook.sh"}]}
            ],
            "PreToolUse": [
              {"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/bin/guard.sh"}]}
            ]
          }
        }
        """
        let result = try mergeClaudeSettings(existing: existing, scriptDir: scriptDir)
        #expect(result.changed)
        let root = object(result.json)
        #expect(root["model"] as? String == "opus")
        let evts = events(result.json)
        #expect(evts["PreToolUse"]?.count == 1)
        #expect(command(evts["PreToolUse"]![0]) == "/usr/bin/guard.sh")
        #expect(evts["UserPromptSubmit"]?.count == 2)
        let commands = evts["UserPromptSubmit"]!.compactMap { command($0) }
        #expect(commands.contains("/usr/bin/other-hook.sh"))
        #expect(commands.contains { $0.hasSuffix("agent-status.sh' active --blink") })
        #expect(evts["PostToolUse"]?.count == 2)
        #expect(evts["Stop"]?.count == 1)
        #expect(evts["Notification"]?.count == 1)
    }

    @Test func mergeRemergePreservesUnrelatedAndStaysNoOp() throws {
        let existing = """
        {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/usr/bin/other.sh"}]}]}}
        """
        let first = try mergeClaudeSettings(existing: existing, scriptDir: scriptDir)
        let second = try mergeClaudeSettings(existing: first.json, scriptDir: scriptDir)
        #expect(!second.changed)
        let commands = events(second.json)["UserPromptSubmit"]!.compactMap { command($0) }
        #expect(commands.contains("/usr/bin/other.sh"))
    }

    @Test func mergeRefusesMalformedExisting() {
        // refusing leaves the user's hand-maintained settings.json untouched
        #expect(throws: AgentHooksInstall.MergeError.self) {
            try mergeClaudeSettings(existing: "{ this is not json", scriptDir: scriptDir)
        }
        #expect(throws: AgentHooksInstall.MergeError.self) {
            try mergeClaudeSettings(existing: "[1, 2, 3]", scriptDir: scriptDir)
        }
    }

    @Test func mergeWhitespaceOnlyStartsFresh() throws {
        // a whitespace-only file has no content to lose, so it starts fresh like an empty file
        let result = try mergeClaudeSettings(existing: "   \n\t\n", scriptDir: scriptDir)
        #expect(result.changed)
        #expect(events(result.json).count == 6)
    }

    @Test func mergeHandlesEmptyExisting() throws {
        let result = try mergeClaudeSettings(existing: "", scriptDir: scriptDir)
        #expect(result.changed)
        #expect(events(result.json).count == 6)
    }

    @Test func mergeAddsBothSessionStartHooksRestoreFirst() throws {
        let result = try mergeClaudeSettings(existing: nil, scriptDir: scriptDir)
        let start = try #require(events(result.json)["SessionStart"])
        #expect(start.count == 2)
        #expect(command(start[0])?.hasPrefix("'\(scriptDir)/agx-session-restore.sh'") == true)
        #expect(command(start[1])?.hasPrefix("'\(scriptDir)/agx-session-context.sh'") == true)
        #expect(start[0]["matcher"] == nil)
        #expect(start[1]["matcher"] == nil)
    }

    @Test func mergeAddsOnlyTheMissingSessionStartHook() throws {
        // an older install carries the restore hook alone: a re-run appends context and keeps restore's entry
        let existing = """
        {"hooks": {"SessionStart": [
          {"hooks": [{"type": "command", "command": "/usr/bin/other-start.sh"}]},
          {"hooks": [{"type": "command", "command": "'\(scriptDir)/agx-session-restore.sh'"}]}
        ]}}
        """
        let result = try mergeClaudeSettings(existing: existing, scriptDir: scriptDir)
        #expect(result.changed)
        let commands = try #require(events(result.json)["SessionStart"]).compactMap { command($0) }
        #expect(commands == [
            "/usr/bin/other-start.sh",
            "'\(scriptDir)/agx-session-restore.sh'",
            "'\(scriptDir)/agx-session-context.sh' --format claude",
        ])
        let again = try mergeClaudeSettings(existing: result.json, scriptDir: scriptDir)
        #expect(!again.changed)
    }

    @Test func mergeSessionStartProbeIsPerScriptNotPerDirectory() throws {
        // a foreign SessionStart hook living in the same directory must not satisfy the probe
        let existing = """
        {"hooks": {"SessionStart": [
          {"hooks": [{"type": "command", "command": "'\(scriptDir)/something-else.sh'"}]}
        ]}}
        """
        let result = try mergeClaudeSettings(existing: existing, scriptDir: scriptDir)
        #expect(try #require(events(result.json)["SessionStart"]).count == 3)
    }

    @Test func codexHooksBlockContainsAllSixEvents() {
        let block = codexHooksBlock(scriptDir: scriptDir)
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"] {
            #expect(block.contains("[[hooks.\(event)]]"))
            #expect(block.contains("[[hooks.\(event).hooks]]"))
        }
        #expect(block.contains("type = \"command\""))
    }

    @Test func codexHooksBlockMapsActionsAndBakesWrapperPath() {
        let block = codexHooksBlock(scriptDir: scriptDir)
        let hook = scriptDir + "/" + codexAdapter
        // Codex-specific behavior stays in the installed adapter; agterm only generates the six
        // lifecycle entries.
        #expect(block.contains("command = \"'\(hook)' session-start\""))
        #expect(block.contains("command = \"'\(hook)' user-prompt-submit\""))
        #expect(block.contains("command = \"'\(hook)' pre-tool-use\""))
        #expect(block.contains("command = \"'\(hook)' post-tool-use\""))
        #expect(block.contains("command = \"'\(hook)' permission-request\""))
        #expect(block.contains("command = \"'\(hook)' stop\""))
        #expect(!block.contains("command = \"'\(AgentHooksInstall.wrapperPath(scriptDir: scriptDir))' blocked\""))
    }

    @Test func codexHooksBlockShellQuotesPathWithSpace() {
        let dir = "/Users/my name/.config/agterm/agent-status"
        let block = codexHooksBlock(scriptDir: dir)
        // the path keeps its space as ONE shell token via single-quoting inside the TOML value
        #expect(block.contains("command = \"'\(dir)/\(codexAdapter)' session-start\""))
    }

    @Test func codexHooksBlockEscapesApostropheInPath() {
        // a username with an apostrophe: shellQuote emits '\'' (a backslash), which the TOML basic
        // string must escape as \\ so the parsed value is a valid /bin/sh command again
        let block = codexHooksBlock(scriptDir: "/Users/O'Brien/agent-status")
        #expect(block.contains("'/Users/O'\\\\''Brien/agent-status/agents/codex/status.sh' session-start"))
    }

    private func mergedContents(_ outcome: AgentHooksInstall.TOMLMergeOutcome) -> String {
        guard case .merged(let contents) = outcome else {
            Issue.record("expected .merged, got \(outcome)")
            return ""
        }
        return contents
    }

    @Test func mergeCodexConfigAppendsHooksToEmpty() {
        let contents = mergedContents(mergeCodexConfig(existing: "", scriptDir: scriptDir))
        #expect(contents.contains(AgentHooksInstall.rcMarkerBegin))
        #expect(contents.contains(AgentHooksInstall.rcMarkerEnd))
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"] {
            #expect(contents.contains("[[hooks.\(event)]]"))
        }
    }

    @Test func mergeCodexConfigIsIdempotent() {
        let first = mergedContents(mergeCodexConfig(existing: "model = \"gpt-5\"\n", scriptDir: scriptDir))
        // second run sees our marker → .unchanged (checked before the hooks-present probe)
        #expect(mergeCodexConfig(existing: first, scriptDir: scriptDir) == .unchanged)
        #expect(first.components(separatedBy: AgentHooksInstall.rcMarkerBegin).count - 1 == 1)
    }

    @Test func mergeCodexConfigUpgradesManagedHooksAndPreservesTrustState() {
        let legacyWrapper = AgentHooksInstall.wrapperPath(scriptDir: scriptDir)
        let existing = """
        model = "gpt-5"

        \(AgentHooksInstall.rcMarkerBegin)
        [[hooks.SessionStart]]
        [[hooks.SessionStart.hooks]]
        type = "command"
        command = "'\(legacyWrapper)' idle"

        [[hooks.PermissionRequest]]
        [[hooks.PermissionRequest.hooks]]
        type = "command"
        command = "'\(legacyWrapper)' blocked"

        [hooks.state]

        [hooks.state."/Users/me/.codex/config.toml:session_start:0:0"]
        trusted_hash = "sha256:stale-but-preserved"
        \(AgentHooksInstall.rcMarkerEnd)
        """
        let contents = mergedContents(mergeCodexConfig(existing: existing, scriptDir: scriptDir))
        let hook = scriptDir + "/" + codexAdapter
        for action in ["session-start", "user-prompt-submit", "pre-tool-use", "post-tool-use", "permission-request", "stop"] {
            #expect(contents.contains("'\(hook)' \(action)"))
        }
        #expect(!contents.contains("'\(legacyWrapper)' blocked"))
        #expect(contents.contains("trusted_hash = \"sha256:stale-but-preserved\""))
        #expect(contents.components(separatedBy: AgentHooksInstall.rcMarkerBegin).count - 1 == 1)
    }

    @Test func mergeCodexConfigDoesNotReplaceForeignMarkerBlock() {
        let existing = """
        \(AgentHooksInstall.rcMarkerBegin)
        # user content that happens to use the same generic markers
        model = "gpt-5"
        \(AgentHooksInstall.rcMarkerEnd)
        """
        #expect(mergeCodexConfig(existing: existing, scriptDir: scriptDir) == .unchanged)
    }

    @Test func mergeCodexConfigStripsLegacyNotifyLine() {
        let existing = "notify = [\"/Users/me/.config/agterm/agent-status/codex-notify.sh\"]\n"
        let contents = mergedContents(mergeCodexConfig(existing: existing, scriptDir: scriptDir))
        #expect(!contents.contains("codex-notify.sh"))
        #expect(contents.contains("[[hooks.Stop]]"))
    }

    @Test func mergeCodexConfigPreservesCommentsAndOtherNotify() {
        let existing = """
        # my codex config
        model = "gpt-5"
        notify = ["/home/me/my-own-notify.sh"]
        """
        let contents = mergedContents(mergeCodexConfig(existing: existing, scriptDir: scriptDir))
        #expect(contents.contains("# my codex config")) // surgical append, no reserialize
        #expect(contents.contains("model = \"gpt-5\""))
        #expect(contents.contains("notify = [\"/home/me/my-own-notify.sh\"]"))
        #expect(contents.contains("[[hooks.PermissionRequest]]"))
        #expect(contents.contains("my-own-notify.sh\"]\n\n\(AgentHooksInstall.rcMarkerBegin)"))
    }

    @Test func mergeCodexConfigKeepsNotifyWhenCodexNameOnlyInComment() {
        // over-match guard: codex-notify.sh appears only in a COMMENT, so the parsed value never names it
        let existing = "notify = [\"/home/me/custom.sh\"] # replaces codex-notify.sh\n"
        let contents = mergedContents(mergeCodexConfig(existing: existing, scriptDir: scriptDir))
        #expect(contents.contains("notify = [\"/home/me/custom.sh\"]"))
    }

    @Test func mergeCodexConfigSkipsWhenUserHasOwnHooks() {
        // appending to a config that already defines hooks would duplicate/break them
        let existing = """
        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "echo done"
        """
        #expect(mergeCodexConfig(existing: existing, scriptDir: scriptDir) == .hooksExist)
    }

    @Test func mergeCodexConfigReportsUnparseable() {
        #expect(mergeCodexConfig(existing: "this = is = not = toml\n", scriptDir: scriptDir) == .unparseable)
    }

    @Test func appendShellRCAddsLineAndMarkersOnce() {
        let result = AgentHooksInstall.appendShellRC(existing: "export FOO=1\n", scriptDir: scriptDir)
        #expect(result.changed)
        #expect(result.contents.contains(AgentHooksInstall.rcMarkerBegin))
        #expect(result.contents.contains(AgentHooksInstall.rcMarkerEnd))
        #expect(result.contents.contains("source '\(scriptDir)/shell/integration.sh'"))
        #expect(result.contents.hasPrefix("export FOO=1\n"))
    }

    @Test func appendShellRCSecondCallIsNoOp() {
        let first = AgentHooksInstall.appendShellRC(existing: "export FOO=1\n", scriptDir: scriptDir)
        let second = AgentHooksInstall.appendShellRC(existing: first.contents, scriptDir: scriptDir)
        #expect(!second.changed)
        #expect(second.contents == first.contents)
        let count = first.contents.components(separatedBy: AgentHooksInstall.rcMarkerBegin).count - 1
        #expect(count == 1)
    }

    @Test func appendShellRCToEmptyFile() {
        let result = AgentHooksInstall.appendShellRC(existing: "", scriptDir: scriptDir)
        #expect(result.changed)
        #expect(result.contents.hasPrefix(AgentHooksInstall.rcMarkerBegin))
    }

    @Test func appendShellRCWithCustomScriptName() {
        let result = AgentHooksInstall.appendShellRC(existing: "export FOO=1\n", scriptDir: scriptDir, scriptName: "shell/integration.fish")
        #expect(result.changed)
        #expect(result.contents.contains("source '\(scriptDir)/shell/integration.fish'"))
    }

    @Test func pluginManifestsNameTheirAutoDiscoveredDestinations() {
        guard case .plugin(let piSource, let piDestination, let piRequires, let piMarker) = agent("pi").status else {
            Issue.record("pi is not a plugin"); return
        }
        #expect(piSource == "agents/pi/extension.ts")
        #expect(piDestination == ".pi/agent/extensions/agterm-status.ts")
        #expect(piRequires == ".pi/agent")
        #expect(piMarker == "// agterm-pi-status-extension")
        guard case .plugin(let source, let destination, let requires, let marker) = agent("opencode").status else {
            Issue.record("opencode is not a plugin"); return
        }
        #expect(source == "agents/opencode/plugin.js")
        #expect(destination == ".config/opencode/plugins/agterm-status.js")
        #expect(requires == ".config/opencode")
        #expect(marker == "// agterm-opencode-status-plugin")
    }

    /// The bundled plugin sources carry the marker their manifest names, or a reinstall would refuse to
    /// refresh them.
    @Test func bundledPluginsCarryTheirOwnershipMarker() throws {
        let package = AgentCatalog.sourceDirectory.deletingLastPathComponent()
        for profile in AgentCatalog.known {
            guard case .plugin(let source, _, _, let marker) = profile.status else { continue }
            let contents = try String(contentsOf: package.appendingPathComponent(source), encoding: .utf8)
            #expect(contents.contains(marker), "\(source) lacks \(marker)")
        }
    }

    @Test func pluginOwnershipProtectsUserFiles() {
        let marker = "// agterm-pi-status-extension"
        #expect(AgentHooksInstall.mayOverwritePlugin(fileExists: false, existingContents: nil, marker: marker))
        #expect(AgentHooksInstall.mayOverwritePlugin(
            fileExists: true, existingContents: "\(marker)\nexport default () => {}\n", marker: marker
        ))
        #expect(!AgentHooksInstall.mayOverwritePlugin(fileExists: true, existingContents: "export default () => {}\n", marker: marker))
        #expect(!AgentHooksInstall.mayOverwritePlugin(fileExists: true, existingContents: nil, marker: marker))
    }

    @Test func shippedShellIntegrationsOmitLifecycleAgentsFromDefaultRegex() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // Keep local to the test — no production constant; shell scripts are the source of truth.
        let expected = "^(gemini|cursor-agent|aider|crush|goose)([[:space:]]|$)"
        let lifecycleAgents = ["opencode", "claude", "codex"]
        for relative in ["agterm/Resources/agent-status/shell/integration.sh",
                         "agterm/Resources/agent-status/shell/integration.fish"] {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            #expect(text.contains(expected), "\(relative) must embed the default agent regex")
            // Match only the default assignment (not commented override examples).
            let defaultLines = text.split(separator: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") { return false }
                return trimmed.contains("AGTERM_AGENT_RE:=")
                    || trimmed.hasPrefix("set -g AGTERM_AGENT_RE ")
            }
            #expect(defaultLines.count == 1, "\(relative) must have exactly one default AGTERM_AGENT_RE")
            for line in defaultLines {
                #expect(String(line).contains(expected))
                for name in lifecycleAgents {
                    #expect(
                        !String(line).contains(name),
                        "\(relative) default must not include \(name)"
                    )
                }
                // "pi" is a substring of other tokens; require a command-name boundary match.
                #expect(
                    line.range(of: #"(^|[|(])pi([)|[:space:]]|$)"#, options: .regularExpression) == nil,
                    "\(relative) default must not include pi as an agent name"
                )
            }
        }
    }

    @Test func backupPathAppendsBak() {
        #expect(AgentHooksInstall.backupPath(for: "/home/me/.claude/settings.json") == "/home/me/.claude/settings.json.bak")
    }

    @Test func backupPathHandlesPathWithoutExtension() {
        #expect(AgentHooksInstall.backupPath(for: "/home/me/.zshrc") == "/home/me/.zshrc.bak")
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agterm-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writeFilePreservesPosixMode() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("settings.json").path
        try "old contents".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: path)
        let mode = AgentHooksInstall.posixMode(ofFile: path)
        try AgentHooksInstall.writeFile("new contents", toPath: path, posixMode: mode)
        #expect(AgentHooksInstall.posixMode(ofFile: path)?.intValue == 0o600)
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "new contents")
    }

    @Test func writeFileWithNilModeCreatesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("fresh.json").path
        try AgentHooksInstall.writeFile("hello", toPath: path, posixMode: nil)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect((try? String(contentsOfFile: path, encoding: .utf8)) == "hello")
        #expect(AgentHooksInstall.posixMode(ofFile: path) != nil)
    }

    @Test func posixModeReturnsModeAndNilForAbsent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("secret").path
        try "x".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: path)
        #expect(AgentHooksInstall.posixMode(ofFile: path)?.intValue == 0o600)
        #expect(AgentHooksInstall.posixMode(ofFile: dir.appendingPathComponent("nope").path) == nil)
    }
}
