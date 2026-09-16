import Foundation
import Testing
@testable import agtermCore

struct DestructiveCommandTests {
    @Test func theNamedShapesAreCaught() {
        #expect(DestructiveCommand.match(in: "rm -rf build")?.name == "rm -rf")
        #expect(DestructiveCommand.match(in: "  rm -fr /tmp/x")?.name == "rm -rf")
        #expect(DestructiveCommand.match(in: "cd x && rm -r dist")?.name == "rm -rf")
        #expect(DestructiveCommand.match(in: "git push --force origin main")?.name == "git push --force")
        #expect(DestructiveCommand.match(in: "git push -f")?.name == "git push --force")
        #expect(DestructiveCommand.match(in: "git push origin +main")?.name == "git push --force")
        #expect(DestructiveCommand.match(in: "sudo launchctl kickstart x")?.name == "sudo")
        #expect(DestructiveCommand.match(in: "git reset --hard HEAD~3")?.name == "git reset --hard")
        #expect(DestructiveCommand.match(in: "psql -c 'DROP TABLE users'")?.name == "DROP")
        #expect(DestructiveCommand.match(in: "drop database prod;")?.name == "DROP")
        #expect(DestructiveCommand.match(in: "TRUNCATE payments")?.name == "TRUNCATE")
        #expect(DestructiveCommand.match(in: "git checkout -- src/")?.name == "git checkout --")
        #expect(DestructiveCommand.match(in: "git clean -fdx")?.name == "git clean -f")
        #expect(DestructiveCommand.match(in: "pm2 restart api")?.name == "service restart")
        #expect(DestructiveCommand.match(in: "docker system prune -a")?.name == "docker rm")
        #expect(DestructiveCommand.match(in: "kill -9 4242")?.name == "kill")
    }

    @Test func ordinaryCommandsPass() {
        for line in ["rm notes.tmp", "git push origin main", "git reset HEAD~1", "git status", "npm test",
                     "ls -la /tmp", "grep -rn drop ./src", "echo the dropdown menu", "cat sudoers.md",
                     "git branch -d old", "dd if=/dev/zero of=./blank.img bs=1m count=1", "kill 4242",
                     "swift test", "chmod +x run.sh", "docker ps", "kubectl get pods", "pip install rmtree"] {
            #expect(DestructiveCommand.match(in: line) == nil, "\(line)")
        }
    }

    @Test func shellPatternsAreCaseSensitiveAndSQLOnesAreNot() {
        #expect(DestructiveCommand.match(in: "Sudo is not needed here.") == nil)
        #expect(DestructiveCommand.match(in: "RM -RF is shouted") == nil)
        #expect(DestructiveCommand.match(in: "Drop Table Users") != nil)
    }
}

struct AutoAnswerPolicyTests {
    private let claudePrompt = """
        ╭──────────────────────────────╮
        │ Bash command                 │
        │   swift test                 │
        │   Run the unit tests         │
        │ Do you want to proceed?      │
        │ ❯ 1. Yes                     │
        │   2. Yes, and don't ask again│
        │   3. No, and tell Claude     │
        ╰──────────────────────────────╯
        """
    private let codexPrompt = """
        Would you like to run the following command?
          $ make build
        › Yes (y)
          No, and tell Codex what to do differently (n)
        Press Enter to confirm or Esc to cancel
        """

    @Test func claudeGetsReturnAndCodexGetsY() {
        #expect(AutoAnswerPolicy.decide(screen: claudePrompt, agent: .claude) == .answer(keys: "\n"))
        #expect(AutoAnswerPolicy.decide(screen: codexPrompt, agent: .codex) == .answer(keys: "y"))
    }

    @Test func aDestructiveCommandOnScreenHolds() {
        let screen = claudePrompt.replacingOccurrences(of: "swift test", with: "rm -rf node_modules")
        #expect(AutoAnswerPolicy.decide(screen: screen, agent: .claude) == .hold(reason: "destructive: rm -rf"))
        let codex = codexPrompt.replacingOccurrences(of: "make build", with: "sudo make install")
        #expect(AutoAnswerPolicy.decide(screen: codex, agent: .codex) == .hold(reason: "destructive: sudo"))
    }

    @Test func destructiveTextAboveTheDialogIsIgnored() {
        let claude = "⏺ Bash(rm -rf node_modules)\n  ⎿  Done\n\n" + claudePrompt
        #expect(AutoAnswerPolicy.decide(screen: claude, agent: .claude) == .answer(keys: "\n"))
        let codex = "• Ran rm -rf /Users/rus/Desktop/aa-junk-dir\n  └ (no output)\n\n" + codexPrompt
        #expect(AutoAnswerPolicy.decide(screen: codex, agent: .codex) == .answer(keys: "y"))
    }

    @Test func aClaudeDialogOpensWithARuleLine() {
        let screen = """
            ⏺ Bash(git push --force)
            ────────────────────────────────
             Bash command
             git branch -D wip
             Delete the branch
             Do you want to proceed?
             ❯ 1. Yes
               3. No
             Esc to cancel · Tab to amend
            """
        #expect(AutoAnswerPolicy.decide(screen: screen, agent: .claude) == .hold(reason: "destructive: git branch -D"))
    }

    @Test func anUnrecognizedDialogLayoutScansTheWholeScreen() {
        let screen = "sudo rm x\nDo you want to proceed? 1. Yes"
        #expect(AutoAnswerPolicy.decide(screen: screen, agent: .claude) == .hold(reason: "destructive: sudo"))
    }

    @Test func aQuestionToTheUserIsNeverAnswered() {
        let askUserQuestion = """
            ──────────────────────────────────────
             ☐ Demo color

            Which color for the demo?

            ❯ 1. Red
                 Warm, energetic
              2. Blue
                 Cool, calm
              4. Type something.
            ──────────────────────────────────────
              5. Chat about this

            Enter to select · ↑/↓ to navigate · Esc to cancel
            """
        #expect(AutoAnswerPolicy.decide(screen: askUserQuestion, agent: .claude) == .hold(reason: "question for the user"))
        let yesNoQuestion = askUserQuestion.replacingOccurrences(of: "Which color for the demo?", with: "Do you want to deploy now?")
            .replacingOccurrences(of: "1. Red", with: "1. Yes")
        #expect(AutoAnswerPolicy.decide(screen: yesNoQuestion, agent: .claude) == .hold(reason: "question for the user"))
        let optionsOnly = "Which color?\n❯ 1. Yes\n  2. No\nEsc to cancel"
        #expect(AutoAnswerPolicy.decide(screen: optionsOnly, agent: .claude) == .hold(reason: "no prompt visible"))
        let codexInput = "Codex needs your input\nWhich branch?\n› main\nEnter to submit"
        #expect(AutoAnswerPolicy.decide(screen: codexInput, agent: .codex) == .hold(reason: "question for the user"))
    }

    private let codexMCPApproval = """
        • Calling codebase-memory-mcp.search_graph({"file_pattern":".*damin-robot/index.html","limit":80})

          Field 1/1 (1 required unanswered)
          Allow the codebase-memory-mcp MCP server to run tool "search_graph"?

          file_pattern: .*damin-robot/index.html
          limit: 80

          › 1. Allow                   Run the tool and continue.
            2. Allow for this session  Run the tool and remember this choice for this session.
            3. Always allow            Run the tool and remember this choice for future tool calls.
            4. Cancel                  Cancel this tool call
          enter to submit | esc to cancel
        """

    @Test func codexMCPToolApprovalGetsReturnNotY() {
        #expect(AutoAnswerPolicy.decide(screen: codexMCPApproval, agent: .codex) == .answer(keys: "\n"))
        let destructive = codexMCPApproval.replacingOccurrences(of: "limit: 80", with: "command: rm -rf build")
        #expect(AutoAnswerPolicy.decide(screen: destructive, agent: .codex) == .hold(reason: "destructive: rm -rf"))
    }

    @Test func nothingToAnswerHolds() {
        #expect(AutoAnswerPolicy.decide(screen: "> \n", agent: .claude) == .hold(reason: "no prompt visible"))
        #expect(AutoAnswerPolicy.decide(screen: "Do you want to proceed?\nEsc to cancel", agent: .claude) == .hold(reason: "no prompt visible"))
        #expect(AutoAnswerPolicy.decide(screen: nil, agent: .claude) == .hold(reason: "pane not readable"))
        #expect(AutoAnswerPolicy.decide(screen: claudePrompt, agent: nil) == .hold(reason: "unknown agent"))
    }

    @Test func agentComesFromTheBinary() {
        #expect(AutoAnswerAgent.of(binary: "claude") == .claude)
        #expect(AutoAnswerAgent.of(binary: "codex") == .codex)
        #expect(AutoAnswerAgent.of(binary: "gemini") == nil)
        #expect(AutoAnswerAgent.of(binary: nil) == nil)
    }

    @Test func stateRecordsCountsAndTheLastDecision() {
        var state = AutoAnswerState()
        let now = Date(timeIntervalSince1970: 100)
        state.dueAt = now
        state.record(.answer(keys: "\n"), at: now)
        #expect(state.dueAt == nil)
        #expect(state.answered == 1 && state.held == 0)
        #expect(state.lastAction == "answered" && state.lastReason == nil && state.lastAt == now)
        state.record(.hold(reason: "destructive: sudo"), at: now)
        #expect(state.held == 1)
        #expect(state.lastAction == "held" && state.lastReason == "destructive: sudo")
    }

    @Test func overrideWinsOverSettings() {
        var state = AutoAnswerState()
        #expect(state.effectiveEnabled(settings: true))
        #expect(!state.effectiveEnabled(settings: false))
        state.enabledOverride = false
        #expect(!state.effectiveEnabled(settings: true))
        state.enabledOverride = true
        #expect(state.effectiveEnabled(settings: false))
    }

    @Test func nodeProjectsSourceDelayAndCounters() {
        var state = AutoAnswerState()
        let plain = ControlAutoAnswerNode.project(state, settingsEnabled: true, delaySeconds: 45)
        #expect(plain == ControlAutoAnswerNode(enabled: true, source: "settings", delaySeconds: 45))
        state.enabledOverride = false
        state.dueAt = Date(timeIntervalSince1970: 0)
        state.record(.hold(reason: "no prompt visible"))
        let held = ControlAutoAnswerNode.project(state, settingsEnabled: true, delaySeconds: 60)
        #expect(held.enabled == false && held.source == "session" && held.delaySeconds == 60)
        #expect(held.dueAt == nil && held.answered == nil && held.held == 1)
        #expect(held.lastAction == "held" && held.lastReason == "no prompt visible")
        state.dueAt = Date(timeIntervalSince1970: 0)
        let due = ControlAutoAnswerNode.project(state, settingsEnabled: true, delaySeconds: 60)
        #expect(due.dueAt == ControlISO8601.string(Date(timeIntervalSince1970: 0)))
    }

    @Test func settingsDefaultOnAtFortyFiveSecondsAndClampTheDelay() {
        #expect(AppSettings().effectiveAutoAnswerEnabled)
        #expect(AppSettings().effectiveAutoAnswerDelaySeconds == 45)
        #expect(!AppSettings(autoAnswerEnabled: false).effectiveAutoAnswerEnabled)
        #expect(AppSettings(autoAnswerDelaySeconds: 90).effectiveAutoAnswerDelaySeconds == 90)
        #expect(AppSettings(autoAnswerDelaySeconds: 0).effectiveAutoAnswerDelaySeconds == 5)
        #expect(AppSettings(autoAnswerDelaySeconds: 99_999).effectiveAutoAnswerDelaySeconds == 600)
    }

    @Test func settingsRoundTripThroughJSON() throws {
        let settings = AppSettings(autoAnswerEnabled: false, autoAnswerDelaySeconds: 120)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.autoAnswerEnabled == false)
        #expect(decoded.autoAnswerDelaySeconds == 120)
    }
}

@MainActor
struct ControlDispatcherAutoAnswerTests {
    @Test func statusIsTheDefaultAndOnOffSetTheOverride() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, target: "S"))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, target: "S", args: ControlArgs(mode: "on", window: "W")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, args: ControlArgs(mode: "off")))
        _ = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, args: ControlArgs(mode: "status")))
        #expect(actions.calls == [
            .setSessionAutoAnswer(target: "S", options: ControlAutoAnswerOptions(window: nil, enable: nil)),
            .setSessionAutoAnswer(target: "S", options: ControlAutoAnswerOptions(window: "W", enable: true)),
            .setSessionAutoAnswer(target: nil, options: ControlAutoAnswerOptions(window: nil, enable: false)),
            .setSessionAutoAnswer(target: nil, options: ControlAutoAnswerOptions(window: nil, enable: nil)),
        ])
    }

    @Test func rejectsAnUnknownModeWithoutCallingHost() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, args: ControlArgs(mode: "toggle")))
        #expect(response == ControlResponse(ok: false, error: "session.autoanswer mode must be on|off|status, not toggle"))
        #expect(actions.calls.isEmpty)
    }

    @Test func forwardsTheHostAnswer() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        let node = ControlAutoAnswerNode(enabled: false, source: "session", delaySeconds: 45)
        actions.nextSetSessionAutoAnswerResponse = ControlResponse(ok: true, result: ControlResult(id: "S", autoAnswer: node))
        let response = await dispatcher.dispatch(ControlRequest(cmd: .sessionAutoAnswer, target: "S", args: ControlArgs(mode: "off")))
        #expect(response?.result?.autoAnswer == node)
    }

    @Test func treeNodeMasksTheGraceOnceTheSessionIsNoLongerBlocked() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agterm-tests-\(UUID().uuidString)")
        let store = AppStore(persistence: PersistenceStore(directory: dir))
        let workspace = store.addWorkspace(name: "work")
        let session = store.addSession(toWorkspace: workspace.id, cwd: "/tmp")!
        store.autoAnswerDelaySeconds = 30
        session.autoAnswer.dueAt = Date(timeIntervalSince1970: 0)
        #expect(store.autoAnswerNode(session).dueAt == nil)
        store.setAgentIndicator(AgentIndicator(status: .blocked), forSession: session.id)
        #expect(store.autoAnswerNode(session).dueAt == ControlISO8601.string(Date(timeIntervalSince1970: 0)))
        #expect(store.autoAnswerNode(session).delaySeconds == 30)
        store.autoAnswerEnabled = false
        #expect(store.autoAnswerNode(session).enabled == false)
        #expect(store.controlTree().workspaces.flatMap(\.sessions).first { $0.id == session.id.uuidString }?.autoAnswer?.enabled == false)
    }
}

struct AutoAnswerPresenceTests {
    @Test func aBackgroundPromptFiresAfterThePlainGrace() {
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: false, idle: 2) == 0)
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: false, idle: nil) == 0)
    }

    @Test func aPromptOnScreenWaitsOutTheUsersLastMove() {
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: true, idle: 10) == 35)
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: true, idle: 45) == 0)
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: true, idle: 300) == 0)
        #expect(AutoAnswerPresence.remainingGrace(delay: 45, userInSession: true, idle: nil) == 0)
    }

    @Test func hudSpecCountsDownAndNamesTheKey() {
        let claude = AutoAnswerHud.spec(remaining: 44.2, agent: .claude)
        #expect(claude.message == "Auto-answer in 45 s")
        #expect(claude.detail?.contains("press Return") == true)
        #expect(claude.position == .topRight)
        #expect(AutoAnswerHud.spec(remaining: 0, agent: .codex).message == "Auto-answer in 0 s")
        #expect(AutoAnswerHud.spec(remaining: 5, agent: .codex).detail?.contains("press y") == true)
        #expect(AutoAnswerHud.spec(remaining: 5, agent: nil).detail?.contains("press Return") == true)
        #expect((claude.message.count + (claude.detail?.count ?? 0)) <= HudSpec.maxTextLength)
    }

    @Test func onlyItsOwnHudIsOwned() {
        #expect(AutoAnswerHud.owns(AutoAnswerHud.spec(remaining: 3, agent: .claude)))
        #expect(!AutoAnswerHud.owns(HudSpec(message: "deploying…")))
        #expect(!AutoAnswerHud.owns(nil))
    }
}
