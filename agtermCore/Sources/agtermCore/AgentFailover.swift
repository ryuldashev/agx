import Foundation

/// What went wrong in an agent pane, as the app classifies it. `modelExhausted` is the per-model usage pool
/// (Claude Code's "out of usage credits… /model to switch") and is the only kind a model switch cures;
/// `accountLimit` (the 5h/7d subscription pool), `auth` and `processExited` need another agent.
public enum AgentFailureKind: String, Codable, Sendable, CaseIterable {
    case modelExhausted = "model-exhausted"
    case accountLimit = "account-limit"
    case auth
    /// Overload / connection / server-side: the turn ended but nothing is wrong with the session, a
    /// "continue" after a pause usually resumes it.
    case transient
    /// Output cap, bad request: retrying the same prompt would fail again.
    case blocked
    /// The model's safeguards refused the request (a false positive on legitimate work, as a rule). Each
    /// model classifies on its own, so one resend and then another model usually gets through.
    case safetyFlagged = "safety-flagged"
    case processExited = "process-exited"
    case unknown
}

/// One reported failure: the raw `StopFailure` error type and message, the classification, and the model
/// named by the message when it names one ("keep using Fable 5.1").
public struct AgentFailure: Equatable, Sendable {
    public let kind: AgentFailureKind
    public let errorType: String
    public let message: String
    public let model: String?

    public init(kind: AgentFailureKind, errorType: String, message: String, model: String? = nil) {
        self.kind = kind
        self.errorType = errorType
        self.message = message
        self.model = model
    }

    /// Classifies a Claude Code `StopFailure` report. `error` is the hook's error type (`rate_limit`,
    /// `authentication_failed`, …); `message` its `last_assistant_message`. The message decides the
    /// `rate_limit` split, since the type alone does not say which pool ran dry.
    public static func classify(error: String, message: String) -> AgentFailure {
        let type = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let named = exhaustedModel(in: text)
        if lower.contains("out of usage credits") || lower.contains("usage credits are required") {
            return AgentFailure(kind: .modelExhausted, errorType: type, message: text, model: named)
        }
        if lower.contains("safeguards flagged") {
            return AgentFailure(kind: .safetyFlagged, errorType: type, message: text, model: flaggedModel(in: text))
        }
        switch type {
        case "rate_limit":
            if lower.contains("hit your") && lower.contains("limit") {
                return AgentFailure(kind: .accountLimit, errorType: type, message: text)
            }
            return AgentFailure(kind: .transient, errorType: type, message: text)
        case "model_not_found":
            return AgentFailure(kind: .modelExhausted, errorType: type, message: text, model: named)
        case "authentication_failed", "oauth_org_not_allowed", "account_on_hold", "billing_error",
             "cloud_credential_error":
            return AgentFailure(kind: .auth, errorType: type, message: text)
        case "overloaded", "server_error":
            return AgentFailure(kind: .transient, errorType: type, message: text)
        case "invalid_request", "max_output_tokens":
            return AgentFailure(kind: .blocked, errorType: type, message: text)
        case "process_exited":
            return AgentFailure(kind: .processExited, errorType: type, message: text)
        default:
            return AgentFailure(kind: .unknown, errorType: type, message: text)
        }
    }

    /// "…to keep using Fable 5.1 or /model…" → "Fable 5.1"; nil when the message names no model.
    static func exhaustedModel(in message: String) -> String? {
        guard let range = message.range(of: "keep using ") else { return nil }
        let tail = message[range.upperBound...]
        let end = tail.range(of: " or ")?.lowerBound ?? tail.firstIndex(of: ".") ?? tail.endIndex
        let name = tail[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// "API Error: Opus 5 (1M context)'s safeguards flagged…" → "Opus 5 (1M context)"; nil for the
    /// generic "This model's safeguards…".
    static func flaggedModel(in message: String) -> String? {
        guard let range = message.range(of: "'s safeguards") else { return nil }
        var head = Substring(message[..<range.lowerBound])
        if let colon = head.range(of: ": ", options: .backwards) { head = head[colon.upperBound...] }
        let name = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.lowercased() == "this model" ? nil : name
    }
}

/// Model names as Claude Code spells them in `/model` arguments and in its error text, reduced to the
/// family that shares a usage pool: `Fable 5.1`, `fable`, `claude-fable-5-1[1m]` are all `fable`.
public enum ModelFamily {
    public static let known = ["fable", "opus", "sonnet", "haiku"]

    /// What a bare alias (`opus`, `opus[1m]`) resolves to today, so a display name can be matched against
    /// it. Bump when Claude Code moves an alias to a new release.
    public static let latest = ["fable": "5.1", "opus": "5", "sonnet": "5", "haiku": "4.5"]

    public static func of(_ model: String) -> String? {
        let lower = model.lowercased()
        return known.first { lower.contains($0) }
    }

    /// The release number in a display name (`Opus 4.8 (1M context)` → `4.8`) or a `/model` argument
    /// (`claude-opus-4-8[1m]` → `4.8`); nil for a bare alias. Bracketed and parenthesised suffixes are
    /// context-window tags, not versions.
    public static func version(of model: String) -> String? {
        var bare = model
        for open in ["[", "("] {
            if let range = bare.range(of: open) { bare = String(bare[..<range.lowerBound]) }
        }
        var digits = ""
        for char in bare {
            if char.isNumber { digits.append(char) } else if !digits.isEmpty {
                if char == "." || char == "-", digits.last != "." { digits.append(".") } else { break }
            }
        }
        while digits.last == "." { digits.removeLast() }
        return digits.isEmpty ? nil : digits
    }

    /// Whether a display name from an error message and a `/model` argument name the same release.
    public static func sameModel(_ displayName: String, _ argument: String) -> Bool {
        guard let family = of(displayName), family == of(argument) else { return false }
        let fallback = latest[family]
        return (version(of: displayName) ?? fallback) == (version(of: argument) ?? fallback)
    }
}

/// What the app does about a failure. Decided host-free by `FailoverPolicy`; the app performs it.
public enum FailoverAction: Equatable, Sendable {
    /// Type `/model <model>` into the pane, then the continue prompt.
    case switchModel(String)
    /// Type the continue prompt after `after` seconds — the turn died of a transient error.
    case retry(after: TimeInterval)
    /// Open a peer session with another agent, seeded with a brief built from the failed session.
    case handoff(reason: String)
    /// Nothing automatic applies; tell the user why.
    case notify(reason: String)

    /// The wire name for `session.failure`'s result, `tree`'s read-back and events.
    public var name: String {
        switch self {
        case .switchModel: return "switch-model"
        case .retry: return "retry"
        case .handoff: return "handoff"
        case .notify: return "notify"
        }
    }
}

/// Per-session failover memory, ephemeral: which model pools this session has already run dry, what it
/// was switched to, how many transient retries it took, and where it was handed off.
public struct FailoverState: Equatable, Sendable {
    public var exhaustedFamilies: [String] = []
    public var switchedTo: String?
    public var switches = 0
    public var retries = 0
    /// Resends after a safeguards flag, counted apart from transient retries: a flag gets one before the
    /// next model is tried.
    public var flagRetries = 0
    /// Every model switched to, so a safeguards flag on the second model does not switch back to the first.
    public var triedModels: [String] = []
    /// Display names of the models whose safeguards refused this session's request, as the errors spelled
    /// them; the model a session STARTED on is only ever known this way.
    public var flaggedModels: [String] = []
    public var handedOffTo: UUID?
    public var lastAction: String?
    public var lastFailureAt: Date?

    public init() {}

    public var isEmpty: Bool { lastAction == nil && handedOffTo == nil }
}

/// The failover rules, pure so the switch/retry/handoff decision is unit-tested without a pane.
public enum FailoverPolicy {
    /// The `/model` arguments tried in order once the current pool is dry, skipping every family already
    /// exhausted in the session. Fable is not here: it is the scarcest pool, the one a session usually
    /// STARTS on, and the one to keep for work that needs it.
    /// Opus 4.8 sits between the two: it shares the Opus usage pool (so an exhausted pool skips it) but
    /// classifies on its own, so a safeguards flag on Opus 5 tries it before dropping to Sonnet.
    public static let defaultModelLadder = ["opus[1m]", "claude-opus-4-8[1m]", "sonnet[1m]"]
    /// Typed into the pane after a model switch or a transient-error pause. Wording matters: the agent
    /// must resume the step it was on, not re-plan from the top.
    public static let defaultContinuePrompt = """
        Continue exactly where you stopped: the previous turn ended with an API error (usage/rate limit or \
        a server error), not because the task was done. Do not restart or re-plan — pick up the last step \
        and carry on.
        """
    /// Typed after a safeguards flag instead of the usage/server-error wording, so the agent does not
    /// treat the refusal as a hint that the task is off limits.
    public static let defaultFlaggedContinuePrompt = """
        Continue exactly where you stopped: the previous turn was refused by the model's safeguards — a \
        false positive on legitimate work, not a verdict on the task. Do not restart or re-plan — pick up \
        the last step and carry on.
        """
    public static let retryDelay: TimeInterval = 20
    public static let maxRetries = 3
    /// A safeguards flag is resent once, soon: the classifier is probabilistic and the same request often
    /// passes the second time.
    public static let flagRetryDelay: TimeInterval = 5
    public static let maxFlagRetries = 1
    /// Retries older than this stop counting against `maxRetries`: three hiccups in a day is not a storm.
    public static let retryWindow: TimeInterval = 30 * 60

    public static func decide(_ failure: AgentFailure, state: FailoverState, ladder: [String],
                              handoffAvailable: Bool, now: Date = Date()) -> FailoverAction {
        switch failure.kind {
        case .modelExhausted:
            var exhausted = Set(state.exhaustedFamilies)
            if let family = failure.model.flatMap(ModelFamily.of) { exhausted.insert(family) }
            if let switched = state.switchedTo.flatMap(ModelFamily.of), failure.model == nil {
                // the message named no model: the one we last switched to is the one that just failed
                exhausted.insert(switched)
            }
            if let next = ladder.first(where: { model in
                guard let family = ModelFamily.of(model) else { return model != state.switchedTo }
                return !exhausted.contains(family)
            }) {
                return .switchModel(next)
            }
            return handoffAvailable
                ? .handoff(reason: "every model in the ladder ran out of usage")
                : .notify(reason: "every model in the ladder ran out of usage and no other agent is connected")
        case .accountLimit:
            return handoffAvailable
                ? .handoff(reason: "the account's usage limit is reached")
                : .notify(reason: "the account's usage limit is reached and no other agent is connected")
        case .auth:
            return handoffAvailable
                ? .handoff(reason: "the agent lost its login")
                : .notify(reason: "the agent lost its login and no other agent is connected")
        case .processExited:
            return handoffAvailable
                ? .handoff(reason: "the agent process exited mid-task")
                : .notify(reason: "the agent process exited mid-task and no other agent is connected")
        case .transient:
            let recent = state.lastFailureAt.map { now.timeIntervalSince($0) <= retryWindow } ?? false
            let retries = recent ? state.retries : 0
            if retries < maxRetries { return .retry(after: retryDelay) }
            return .notify(reason: "\(maxRetries) retries after transient errors did not get the agent going")
        case .safetyFlagged:
            let recent = state.lastFailureAt.map { now.timeIntervalSince($0) <= retryWindow } ?? false
            if (recent ? state.flagRetries : 0) < maxFlagRetries { return .retry(after: flagRetryDelay) }
            var flagged = state.flaggedModels
            if let model = failure.model { flagged.append(model) }
            if let next = ladder.first(where: { model in
                guard !state.triedModels.contains(model), model != state.switchedTo else { return false }
                return !flagged.contains { ModelFamily.sameModel($0, model) }
            }) {
                return .switchModel(next)
            }
            return handoffAvailable
                ? .handoff(reason: "every model in the ladder refused the request")
                : .notify(reason: "every model in the ladder refused the request and no other agent is connected")
        case .blocked:
            return .notify(reason: "the request itself was refused; retrying would fail the same way")
        case .unknown:
            return .notify(reason: "unrecognised agent failure")
        }
    }

    /// Applies the decided action's bookkeeping to the state.
    public static func advance(_ state: FailoverState, failure: AgentFailure, action: FailoverAction,
                               now: Date = Date()) -> FailoverState {
        var next = state
        next.lastAction = action.name
        next.lastFailureAt = now
        if failure.kind == .modelExhausted, let family = failure.model.flatMap(ModelFamily.of),
           !next.exhaustedFamilies.contains(family) {
            next.exhaustedFamilies.append(family)
        }
        if failure.kind == .safetyFlagged, let model = failure.model, !next.flaggedModels.contains(model) {
            next.flaggedModels.append(model)
        }
        switch action {
        case .switchModel(let model):
            if failure.kind == .modelExhausted, failure.model == nil,
               let family = state.switchedTo.flatMap(ModelFamily.of), !next.exhaustedFamilies.contains(family) {
                next.exhaustedFamilies.append(family)
            }
            next.switchedTo = model
            next.triedModels.append(model)
            next.switches += 1
            next.retries = 0
            next.flagRetries = 0
        case .retry:
            let recent = state.lastFailureAt.map { now.timeIntervalSince($0) <= retryWindow } ?? false
            if failure.kind == .safetyFlagged {
                next.flagRetries = (recent ? state.flagRetries : 0) + 1
            } else {
                next.retries = (recent ? state.retries : 0) + 1
            }
        case .handoff, .notify:
            break
        }
        return next
    }
}

/// The agent CLI a session runs, read off its launch or restore line (`exec claude "$b"`,
/// `claude --resume …`, `codex`), so a handoff picks an agent of ANOTHER kind.
public enum AgentBinary {
    /// The binary name when the shell line names one of the known agents, nil otherwise.
    public static func of(commandLine: String?) -> String? {
        AgentCatalog.profile(forCommandLine: commandLine)?.binary
    }
}

/// Reads what a handoff brief needs out of a Claude Code transcript (`~/.claude/projects/<dir>/<id>.jsonl`):
/// the user's last prompts and the agent's last real answer. Pure line parsing, so a hand-made transcript
/// tests it.
public enum ClaudeTranscript {
    /// Claude Code's project directory for a cwd: every non-alphanumeric character becomes `-`.
    public static func projectDirectoryName(cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    public static func transcriptPath(home: String, cwd: String, sessionID: String) -> String {
        home + "/.claude/projects/" + projectDirectoryName(cwd: cwd) + "/" + sessionID + ".jsonl"
    }

    /// The `--resume <id>` argument of a restore line the SessionStart hook pinned, nil when absent.
    public static func sessionID(fromRestoreCommand command: String?) -> String? {
        guard let command, let range = command.range(of: "--resume ") else { return nil }
        let rest = command[range.upperBound...]
        let id = rest.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return id.isEmpty ? nil : String(id)
    }

    public struct Digest: Equatable, Sendable {
        public var prompts: [String]
        public var lastAnswer: String?

        public init(prompts: [String] = [], lastAnswer: String? = nil) {
            self.prompts = prompts
            self.lastAnswer = lastAnswer
        }
    }

    /// The last `maxPrompts` things the user typed (not tool results, not slash-command echoes, not
    /// sidechains) and the last assistant text that was not an API error, each cut to `maxChars`.
    public static func digest(jsonl: String, maxPrompts: Int = 3, maxChars: Int = 1500) -> Digest {
        var prompts: [String] = []
        var lastAnswer: String?
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["isSidechain"] as? Bool != true, object["isMeta"] as? Bool != true,
                  let message = object["message"] as? [String: Any] else { continue }
            switch object["type"] as? String {
            case "user":
                guard let text = userText(message), !isCommandEcho(text) else { continue }
                prompts.append(cut(text, maxChars))
            case "assistant":
                guard object["isApiErrorMessage"] as? Bool != true, let text = assistantText(message) else { continue }
                lastAnswer = cut(text, maxChars)
            default:
                continue
            }
        }
        return Digest(prompts: Array(prompts.suffix(maxPrompts)), lastAnswer: lastAnswer)
    }

    private static func userText(_ message: [String: Any]) -> String? {
        if let text = message["content"] as? String { return text.trimmedOrNil }
        guard let parts = message["content"] as? [[String: Any]] else { return nil }
        let texts = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }
        return texts.joined(separator: "\n").trimmedOrNil
    }

    private static func assistantText(_ message: [String: Any]) -> String? {
        guard let parts = message["content"] as? [[String: Any]] else { return nil }
        let texts = parts.compactMap { part -> String? in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }
        return texts.joined(separator: "\n").trimmedOrNil
    }

    private static func isCommandEcho(_ text: String) -> Bool {
        text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") || text.hasPrefix("<system-reminder>")
            || text.hasPrefix("<task-notification>") || text.hasPrefix("[Request interrupted")
    }

    private static func cut(_ text: String, _ maxChars: Int) -> String {
        text.count <= maxChars ? text : String(text.prefix(maxChars)) + " […]"
    }
}

/// The first message the takeover agent gets: what happened, where the work is, what the user asked, what
/// was done last. Self-contained, the way `agx spawn` briefs are, since the new agent cannot ask back.
public struct HandoffBrief {
    public var reason: String
    public var sourceName: String
    public var sourceAgent: String?
    public var cwd: String
    public var transcriptPath: String?
    public var digest: ClaudeTranscript.Digest

    public init(reason: String, sourceName: String, sourceAgent: String?, cwd: String,
                transcriptPath: String?, digest: ClaudeTranscript.Digest) {
        self.reason = reason
        self.sourceName = sourceName
        self.sourceAgent = sourceAgent
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.digest = digest
    }

    public func compose() -> String {
        var lines: [String] = []
        let from = sourceAgent.map { "a \($0) session" } ?? "another agent's session"
        lines.append("You are taking over an unfinished task from \(from) named \"\(sourceName)\" that stopped: \(reason).")
        lines.append("Working directory: \(cwd). Continue the task from where it stopped; do not start over.")
        if let transcriptPath {
            lines.append("The full conversation so far is the Claude Code transcript at \(transcriptPath) "
                + "(JSONL; `type: user` entries are the user's requests, `type: assistant` the work done). "
                + "Read its tail first if the summary below is not enough.")
        }
        if !digest.prompts.isEmpty {
            lines.append("")
            lines.append("What the user asked (most recent last):")
            for prompt in digest.prompts {
                lines.append("---")
                lines.append(prompt)
            }
        }
        if let answer = digest.lastAnswer {
            lines.append("---")
            lines.append("")
            lines.append("The previous agent's last message before it stopped:")
            lines.append(answer)
        }
        lines.append("")
        lines.append("Work incrementally and write results to files as you go, so an interruption leaves half "
            + "the work rather than nothing. When the task is done, say so plainly.")
        return lines.joined(separator: "\n")
    }
}

/// `tree` read-back of a session's failover memory; nil/omitted while nothing has happened.
public struct ControlFailoverNode: Codable, Sendable, Equatable {
    public let lastAction: String
    public let switchedTo: String?
    public let switches: Int?
    public let retries: Int?
    public let flagRetries: Int?
    public let exhausted: [String]?
    public let tried: [String]?
    public let flagged: [String]?
    public let handedOffTo: String?

    public init(lastAction: String, switchedTo: String? = nil, switches: Int? = nil, retries: Int? = nil,
                flagRetries: Int? = nil, exhausted: [String]? = nil, tried: [String]? = nil,
                flagged: [String]? = nil, handedOffTo: String? = nil) {
        self.lastAction = lastAction
        self.switchedTo = switchedTo
        self.switches = switches
        self.retries = retries
        self.flagRetries = flagRetries
        self.exhausted = exhausted
        self.tried = tried
        self.flagged = flagged
        self.handedOffTo = handedOffTo
    }

    public static func project(_ state: FailoverState) -> ControlFailoverNode? {
        guard let lastAction = state.lastAction else { return nil }
        return ControlFailoverNode(lastAction: lastAction, switchedTo: state.switchedTo,
                                   switches: state.switches > 0 ? state.switches : nil,
                                   retries: state.retries > 0 ? state.retries : nil,
                                   flagRetries: state.flagRetries > 0 ? state.flagRetries : nil,
                                   exhausted: state.exhaustedFamilies.isEmpty ? nil : state.exhaustedFamilies,
                                   tried: state.triedModels.isEmpty ? nil : state.triedModels,
                                   flagged: state.flaggedModels.isEmpty ? nil : state.flaggedModels,
                                   handedOffTo: state.handedOffTo?.uuidString)
    }
}

/// What `session.failure` carries into the host after the dispatcher validated it.
public struct ControlFailureOptions: Equatable, Sendable {
    public let window: String?
    public let error: String
    public let message: String
    public let transcript: String?
    /// `--handoff`: skip the model ladder and hand the task to another agent now.
    public let forceHandoff: Bool

    public init(window: String?, error: String, message: String, transcript: String?, forceHandoff: Bool) {
        self.window = window
        self.error = error
        self.message = message
        self.transcript = transcript
        self.forceHandoff = forceHandoff
    }
}
