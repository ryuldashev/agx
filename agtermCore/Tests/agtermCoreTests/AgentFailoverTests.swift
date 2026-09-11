import Foundation
import Testing
@testable import agtermCore

struct AgentFailureClassifyTests {
    @Test func outOfUsageCreditsIsModelExhaustedAndNamesTheModel() {
        let failure = AgentFailure.classify(
            error: "rate_limit",
            message: "You're out of usage credits. Run /usage-credits to keep using Fable 5.1 or /model to switch models.")
        #expect(failure.kind == .modelExhausted)
        #expect(failure.model == "Fable 5.1")
        #expect(ModelFamily.of(failure.model ?? "") == "fable")
    }

    @Test func usageCreditsRequiredIsModelExhaustedWithoutAModel() {
        let failure = AgentFailure.classify(error: "rate_limit", message: "Usage credits are required for this model.")
        #expect(failure.kind == .modelExhausted)
        #expect(failure.model == nil)
    }

    @Test func weeklyAndSessionLimitsAreAccountLimits() {
        #expect(AgentFailure.classify(error: "rate_limit",
                                      message: "You've hit your weekly limit · resets Jul 9 at 3pm (Asia/Tashkent)").kind == .accountLimit)
        #expect(AgentFailure.classify(error: "rate_limit",
                                      message: "You've hit your session limit · resets 11:00am (Asia/Tashkent)").kind == .accountLimit)
    }

    @Test func typesMapToKinds() {
        #expect(AgentFailure.classify(error: "rate_limit", message: "API Error: Rate limit reached").kind == .transient)
        #expect(AgentFailure.classify(error: "overloaded", message: "API Error: 529 Overloaded").kind == .transient)
        #expect(AgentFailure.classify(error: "server_error", message: "API Error: Unable to connect").kind == .transient)
        #expect(AgentFailure.classify(error: "authentication_failed", message: "Login expired · Please run /login").kind == .auth)
        #expect(AgentFailure.classify(error: "billing_error", message: "").kind == .auth)
        #expect(AgentFailure.classify(error: "invalid_request", message: "safety measures flagged").kind == .blocked)
        #expect(AgentFailure.classify(error: "max_output_tokens", message: "").kind == .blocked)
        #expect(AgentFailure.classify(error: "model_not_found", message: "").kind == .modelExhausted)
        #expect(AgentFailure.classify(error: "process_exited", message: "").kind == .processExited)
        #expect(AgentFailure.classify(error: "something_new", message: "").kind == .unknown)
    }

    @Test func modelFamilies() {
        #expect(ModelFamily.of("Fable 5.1") == "fable")
        #expect(ModelFamily.of("opus[1m]") == "opus")
        #expect(ModelFamily.of("claude-sonnet-5") == "sonnet")
        #expect(ModelFamily.of("Opus 5 (1M context)") == "opus")
        #expect(ModelFamily.of("gpt-6") == nil)
    }

    @Test func agentBinaryFromLaunchLines() {
        #expect(AgentBinary.of(commandLine: "/bin/zsh -lc 'b=\"$(cat /tmp/x)\"; rm -f /tmp/x; exec claude \"$b\"'") == "claude")
        #expect(AgentBinary.of(commandLine: "zsh -lc 'exec claude --resume abc --fork-session'") == "claude")
        #expect(AgentBinary.of(commandLine: "codex --model gpt-6") == "codex")
        #expect(AgentBinary.of(commandLine: "/usr/local/bin/codex") == "codex")
        #expect(AgentBinary.of(commandLine: "vim notes.md") == nil)
        #expect(AgentBinary.of(commandLine: nil) == nil)
    }
}

struct FailoverPolicyTests {
    private let ladder = FailoverPolicy.defaultModelLadder
    private let fable = AgentFailure(kind: .modelExhausted, errorType: "rate_limit", message: "", model: "Fable 5.1")

    @Test func firstExhaustionSwitchesToTheTopOfTheLadder() {
        let action = FailoverPolicy.decide(fable, state: FailoverState(), ladder: ladder, handoffAvailable: true)
        #expect(action == .switchModel("opus[1m]"))
    }

    @Test func secondExhaustionSkipsTheFamilyAlreadySwitchedTo() {
        var state = FailoverPolicy.advance(FailoverState(), failure: fable, action: .switchModel("opus[1m]"))
        #expect(state.exhaustedFamilies == ["fable"])
        #expect(state.switchedTo == "opus[1m]")
        #expect(state.switches == 1)
        let opusOut = AgentFailure(kind: .modelExhausted, errorType: "rate_limit", message: "", model: "Opus 5")
        let action = FailoverPolicy.decide(opusOut, state: state, ladder: ladder, handoffAvailable: true)
        #expect(action == .switchModel("sonnet[1m]"))
        state = FailoverPolicy.advance(state, failure: opusOut, action: action)
        #expect(state.exhaustedFamilies == ["fable", "opus"])
    }

    @Test func anUnnamedExhaustionCountsTheModelSwitchedTo() {
        let state = FailoverPolicy.advance(FailoverState(), failure: fable, action: .switchModel("opus[1m]"))
        let unnamed = AgentFailure(kind: .modelExhausted, errorType: "rate_limit", message: "", model: nil)
        #expect(FailoverPolicy.decide(unnamed, state: state, ladder: ladder, handoffAvailable: true) == .switchModel("sonnet[1m]"))
        let advanced = FailoverPolicy.advance(state, failure: unnamed, action: .switchModel("sonnet[1m]"))
        #expect(advanced.exhaustedFamilies == ["fable", "opus"])
    }

    @Test func aSpentLadderHandsOffOrNotifies() {
        var state = FailoverState()
        state.exhaustedFamilies = ["fable", "opus", "sonnet"]
        #expect(FailoverPolicy.decide(fable, state: state, ladder: ladder, handoffAvailable: true)
            == .handoff(reason: "every model in the ladder ran out of usage"))
        if case .notify = FailoverPolicy.decide(fable, state: state, ladder: ladder, handoffAvailable: false) {} else {
            Issue.record("expected notify without a handoff agent")
        }
    }

    @Test func aCustomLadderIsFollowedInOrder() {
        let action = FailoverPolicy.decide(fable, state: FailoverState(), ladder: ["fable", "haiku"], handoffAvailable: true)
        #expect(action == .switchModel("haiku"))
    }

    @Test func accountAuthAndExitHandOff() {
        for kind in [AgentFailureKind.accountLimit, .auth, .processExited] {
            let failure = AgentFailure(kind: kind, errorType: "x", message: "")
            if case .handoff = FailoverPolicy.decide(failure, state: FailoverState(), ladder: ladder, handoffAvailable: true) {
            } else { Issue.record("\(kind) should hand off") }
            if case .notify = FailoverPolicy.decide(failure, state: FailoverState(), ladder: ladder, handoffAvailable: false) {
            } else { Issue.record("\(kind) should notify without an agent") }
        }
    }

    @Test func transientRetriesThreeTimesThenNotifies() {
        let now = Date()
        let failure = AgentFailure(kind: .transient, errorType: "overloaded", message: "")
        var state = FailoverState()
        for _ in 0..<FailoverPolicy.maxRetries {
            let action = FailoverPolicy.decide(failure, state: state, ladder: ladder, handoffAvailable: true, now: now)
            #expect(action == .retry(after: FailoverPolicy.retryDelay))
            state = FailoverPolicy.advance(state, failure: failure, action: action, now: now)
        }
        #expect(state.retries == FailoverPolicy.maxRetries)
        if case .notify = FailoverPolicy.decide(failure, state: state, ladder: ladder, handoffAvailable: true, now: now) {} else {
            Issue.record("expected notify after the retry cap")
        }
        // an old storm does not count against a new one
        let later = now.addingTimeInterval(FailoverPolicy.retryWindow + 1)
        #expect(FailoverPolicy.decide(failure, state: state, ladder: ladder, handoffAvailable: true, now: later)
            == .retry(after: FailoverPolicy.retryDelay))
        #expect(FailoverPolicy.advance(state, failure: failure, action: .retry(after: 1), now: later).retries == 1)
    }

    @Test func blockedAndUnknownOnlyNotify() {
        for kind in [AgentFailureKind.blocked, .unknown] {
            let failure = AgentFailure(kind: kind, errorType: "x", message: "")
            if case .notify = FailoverPolicy.decide(failure, state: FailoverState(), ladder: ladder, handoffAvailable: true) {
            } else { Issue.record("\(kind) should only notify") }
        }
    }

    @Test func nodeProjectsOnlyAfterAnAction() {
        #expect(ControlFailoverNode.project(FailoverState()) == nil)
        let state = FailoverPolicy.advance(FailoverState(), failure: fable, action: .switchModel("opus[1m]"))
        let node = ControlFailoverNode.project(state)
        #expect(node?.lastAction == "switch-model")
        #expect(node?.switchedTo == "opus[1m]")
        #expect(node?.switches == 1)
        #expect(node?.retries == nil)
        #expect(node?.exhausted == ["fable"])
    }
}

struct ClaudeTranscriptTests {
    @Test func projectDirectoryAndTranscriptPath() {
        #expect(ClaudeTranscript.projectDirectoryName(cwd: "/Users/rus/mmee") == "-Users-rus-mmee")
        #expect(ClaudeTranscript.projectDirectoryName(cwd: "/Users/rus/.claude/x_y") == "-Users-rus--claude-x-y")
        #expect(ClaudeTranscript.transcriptPath(home: "/Users/rus", cwd: "/Users/rus/mmee", sessionID: "abc")
            == "/Users/rus/.claude/projects/-Users-rus-mmee/abc.jsonl")
    }

    @Test func sessionIDFromRestoreCommand() {
        #expect(ClaudeTranscript.sessionID(fromRestoreCommand: "zsh -lc 'exec claude --resume 184bd977-fefc-4954-b8b4-61850f771f21 --fork-session'")
            == "184bd977-fefc-4954-b8b4-61850f771f21")
        #expect(ClaudeTranscript.sessionID(fromRestoreCommand: "claude") == nil)
        #expect(ClaudeTranscript.sessionID(fromRestoreCommand: nil) == nil)
    }

    @Test func digestKeepsTypedPromptsAndTheLastRealAnswer() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"first ask"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working on it"}]}}"#,
            #"{"type":"user","isSidechain":true,"message":{"role":"user","content":"sidechain noise"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"tool output"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"meta"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"second ask"}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done step 2"}]}}"#,
            #"{"type":"assistant","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You're out of usage credits."}]}}"#,
            "not json",
        ]
        let digest = ClaudeTranscript.digest(jsonl: lines.joined(separator: "\n"), maxPrompts: 3)
        #expect(digest.prompts == ["first ask", "second ask"])
        #expect(digest.lastAnswer == "done step 2")
    }

    @Test func digestCutsLongTextAndKeepsTheLastPrompts() {
        let long = String(repeating: "x", count: 50)
        let lines = (1...5).map { #"{"type":"user","message":{"role":"user","content":"ask \#($0) \#(long)"}}"# }
        let digest = ClaudeTranscript.digest(jsonl: lines.joined(separator: "\n"), maxPrompts: 2, maxChars: 10)
        #expect(digest.prompts == ["ask 4 xxxx […]", "ask 5 xxxx […]"])
    }

    @Test func briefNamesReasonPlaceTranscriptAndPrompts() {
        let brief = HandoffBrief(reason: "the agent process exited mid-task", sourceName: "Payroll",
                                 sourceAgent: "claude", cwd: "/Users/rus/mars",
                                 transcriptPath: "/Users/rus/.claude/projects/-Users-rus-mars/abc.jsonl",
                                 digest: ClaudeTranscript.Digest(prompts: ["fix the payroll export"],
                                                                 lastAnswer: "I found the bug in export.py")).compose()
        #expect(brief.contains("a claude session named \"Payroll\" that stopped: the agent process exited mid-task"))
        #expect(brief.contains("Working directory: /Users/rus/mars."))
        #expect(brief.contains("/Users/rus/.claude/projects/-Users-rus-mars/abc.jsonl"))
        #expect(brief.contains("fix the payroll export"))
        #expect(brief.contains("I found the bug in export.py"))
        #expect(brief.contains("do not start over"))
    }

    @Test func briefWithoutTranscriptOrDigestStillStandsAlone() {
        let brief = HandoffBrief(reason: "x", sourceName: "S", sourceAgent: nil, cwd: "/tmp",
                                 transcriptPath: nil, digest: ClaudeTranscript.Digest()).compose()
        #expect(brief.contains("another agent's session"))
        #expect(!brief.contains("transcript"))
        #expect(!brief.contains("What the user asked"))
    }
}

@MainActor
struct ControlDispatcherFailureTests {
    @Test func requiresAnErrorTypeWithoutCallingHost() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        let missing = await dispatcher.dispatch(ControlRequest(cmd: .sessionFailure))
        let blank = await dispatcher.dispatch(ControlRequest(cmd: .sessionFailure, args: ControlArgs(error: " ")))
        #expect(missing?.ok == false)
        #expect(blank?.ok == false)
        #expect(missing?.error == "session.failure requires an error type (rate_limit, server_error, …)")
        #expect(actions.calls.isEmpty)
    }

    @Test func rejectsAMultiWordErrorTypeAndARelativeTranscript() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        let spaced = await dispatcher.dispatch(ControlRequest(cmd: .sessionFailure, args: ControlArgs(error: "rate limit")))
        #expect(spaced == ControlResponse(ok: false, error: "error type must be a single token"))
        let relative = await dispatcher.dispatch(ControlRequest(cmd: .sessionFailure,
                                                                args: ControlArgs(error: "rate_limit", transcript: "x.jsonl")))
        #expect(relative == ControlResponse(ok: false, error: "transcript path must be absolute: x.jsonl"))
        #expect(actions.calls.isEmpty)
    }

    @Test func forwardsTheValidatedOptions() async {
        let actions = MockControlActions()
        let dispatcher = ControlDispatcher(actions: actions)
        let node = ControlFailoverNode(lastAction: "switch-model", switchedTo: "opus[1m]")
        actions.nextReportFailureResponse = ControlResponse(ok: true, result: ControlResult(id: "S", failover: node))
        let response = await dispatcher.dispatch(ControlRequest(
            cmd: .sessionFailure, target: "S",
            args: ControlArgs(message: " out of credits\u{1b} ", window: "W", error: " rate_limit ",
                              transcript: "/t/a.jsonl", handoff: true)))
        #expect(response?.result?.failover == node)
        #expect(actions.calls == [.reportFailure(target: "S", options: ControlFailureOptions(
            window: "W", error: "rate_limit", message: "out of credits", transcript: "/t/a.jsonl", forceHandoff: true))])
    }

    @Test func settingsResolveTheHandoffAgent() {
        let claude = AgentDefinition(name: "Claude Code", command: "claude")
        let codex = AgentDefinition(name: "Codex", command: "codex")
        var settings = AppSettings(agents: [claude, codex])
        #expect(settings.failoverHandoffAgent(for: "claude") == codex)
        #expect(settings.failoverHandoffAgent(for: "codex") == claude)
        settings.failoverHandoffAgent = "codex"
        #expect(settings.failoverHandoffAgent(for: "codex") == codex)
        settings.failoverHandoffAgent = codex.id.uuidString
        #expect(settings.failoverHandoffAgent(for: "claude") == codex)
        #expect(AppSettings(agents: [claude]).failoverHandoffAgent(for: "claude") == nil)
        #expect(AppSettings().effectiveFailoverModels == FailoverPolicy.defaultModelLadder)
        #expect(AppSettings(failoverModels: [" ", "haiku"]).effectiveFailoverModels == ["haiku"])
        #expect(AppSettings(failoverContinuePrompt: " ").effectiveFailoverContinuePrompt == FailoverPolicy.defaultContinuePrompt)
    }
}
