import Foundation

/// A command shape the app must never approve on the user's behalf. Matched against the VISIBLE text of the
/// pane at the moment the grace runs out — the same text the user would have read — so the check sees exactly
/// what the agent is asking to run, whichever agent (Claude Code, Codex) is asking. Shell patterns are
/// case-sensitive (a `Sudo` prose word is not a command), SQL ones are not.
public struct DestructiveCommand: Equatable, Sendable {
    public let name: String
    let pattern: NSRegularExpression

    init(_ name: String, _ pattern: String, caseInsensitive: Bool = false) {
        self.name = name
        // the patterns are literals in this file; a typo fails every test that touches the catalog.
        // swiftlint:disable:next force_try
        self.pattern = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    public static func == (lhs: DestructiveCommand, rhs: DestructiveCommand) -> Bool { lhs.name == rhs.name }

    /// The catalog, first match wins. Biased toward refusing: a false positive costs the user one manual
    /// answer, a false negative runs the command.
    public static let catalog: [DestructiveCommand] = [
        DestructiveCommand("rm -rf", #"(^|[\s;&|(`])rm\s+(-[A-Za-z]*[rRf][A-Za-z]*\s+|--recursive\s+|--force\s+)"#),
        DestructiveCommand("git push --force", #"git\s+push\b[^\n]*?(\s--force\b|\s-f\b|\s--force-with-lease\b|\s\+\S)"#),
        DestructiveCommand("sudo", #"(^|[\s;&|(`])sudo\s"#),
        DestructiveCommand("git reset --hard", #"git\s+reset\b[^\n]*?\s--hard\b"#),
        DestructiveCommand("git checkout --", #"git\s+(checkout|restore)\s+(--\s|\.\s|\.$)"#),
        DestructiveCommand("git clean -f", #"git\s+clean\b[^\n]*?\s-[A-Za-z]*f"#),
        DestructiveCommand("git branch -D", #"git\s+branch\s+(-D|--delete\s+--force|-[a-zA-Z]*D)\b"#),
        DestructiveCommand("git stash drop", #"git\s+stash\s+(drop|clear)\b"#),
        DestructiveCommand("DROP", #"\bDROP\s+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|USER|ROLE|COLLECTION)\b"#, caseInsensitive: true),
        DestructiveCommand("TRUNCATE", #"\bTRUNCATE\s+(TABLE\s+)?\w"#, caseInsensitive: true),
        DestructiveCommand("DELETE FROM", #"\bDELETE\s+FROM\s+\w"#, caseInsensitive: true),
        DestructiveCommand("dd", #"(^|[\s;&|(`])dd\s+[^\n]*\bof=/dev/"#),
        DestructiveCommand("mkfs", #"(^|[\s;&|(`])mkfs(\.\w+)?\s"#),
        DestructiveCommand("diskutil erase", #"diskutil\s+(erase\w*|partitionDisk|reformat)\b"#),
        DestructiveCommand("chmod -R", #"(^|[\s;&|(`])ch(mod|own)\s+-[A-Za-z]*R"#),
        DestructiveCommand("kill", #"(^|[\s;&|(`])(kill\s+-9|kill\s+-KILL|killall|pkill)\s"#),
        DestructiveCommand("shutdown", #"(^|[\s;&|(`])(shutdown|reboot|halt)\b"#),
        DestructiveCommand("launchctl bootout", #"launchctl\s+(bootout|unload|remove)\b"#),
        DestructiveCommand("service restart", #"(systemctl|service|pm2|supervisorctl)\s+(stop|restart|delete|kill|disable)\b"#),
        DestructiveCommand("docker rm", #"docker\s+(rm|rmi|system\s+prune|volume\s+(rm|prune)|container\s+(rm|prune))\b"#),
        DestructiveCommand("kubectl delete", #"kubectl\s+(delete|drain)\b"#),
        DestructiveCommand("fork bomb", #":\(\)\s*\{"#),
    ]

    /// The first catalog entry found in `text`, nil when none.
    public static func match(in text: String) -> DestructiveCommand? {
        let range = NSRange(text.startIndex..., in: text)
        return catalog.first { $0.pattern.firstMatch(in: text, range: range) != nil }
    }
}

/// The agent CLIs the app knows how to say yes to, and the key that does it in each TUI.
public enum AutoAnswerAgent: String, Sendable, CaseIterable {
    case claude
    case codex

    /// Claude Code's permission dialog is a list with "Yes" highlighted, so Return picks it; Codex's approval
    /// overlay binds `y` to approve. The Return is a single key event, not a typed burst, so the paste
    /// detection that swallowed the failover prompt's Return (2026-09-11) does not apply.
    public var affirmativeKeys: String {
        switch self {
        case .claude: return "\n"
        case .codex: return "y"
        }
    }

    /// Lower-cased fragments that prove a permission prompt is actually on screen. Claude Code phrases every
    /// tool prompt as a "Do you want …?" question over a numbered list; Codex's approval overlay and its
    /// question dialogs carry the footer the Codex status hook already keys on.
    public var promptMarkers: [String] {
        switch self {
        case .claude: return ["do you want to", "1. yes", "esc to cancel"]
        case .codex: return ["allow command?", "press enter to confirm", "enter to submit", "would you like to run", "(y)"]
        }
    }

    public static func of(binary: String?) -> AutoAnswerAgent? {
        binary.flatMap(AutoAnswerAgent.init(rawValue:))
    }

    /// The lines the destructive check reads: the open dialog, from its first line to the end of the screen.
    /// Codex's dialog opens with its question and the command follows; Claude Code's opens with a rule (or box
    /// top) above the tool box, the question below the command. A wider scan held safe prompts on a
    /// `rm -rf` still visible from an EARLIER, already-approved step (2026-09-15). When no opening line is
    /// found the whole screen is returned, which errs toward holding.
    public func dialogRegion(of screen: String) -> String {
        let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        let lower = lines.map { $0.lowercased() }
        guard let marker = lower.lastIndex(where: { line in promptMarkers.contains { line.contains($0) } }) else {
            return screen
        }
        let opens: (String) -> Bool
        switch self {
        case .codex:
            opens = { $0.contains("would you like to run") || $0.contains("allow command?") }
        case .claude:
            opens = { line in
                let rule = line.trimmingCharacters(in: .whitespaces)
                return rule.count >= 8 && rule.allSatisfy { "╭─╮│".contains($0) }
            }
        }
        guard let start = lower[...marker].lastIndex(where: opens) else { return screen }
        return lines[start...].joined(separator: "\n")
    }
}

/// What the app does when a session's grace runs out. Decided host-free by `AutoAnswerPolicy`; the app performs it.
public enum AutoAnswerDecision: Equatable, Sendable {
    /// Inject `keys` into the blocked pane.
    case answer(keys: String)
    /// Leave the prompt to the user; `reason` is the wire text.
    case hold(reason: String)

    public var name: String {
        switch self {
        case .answer: return "answered"
        case .hold: return "held"
        }
    }

    public var reason: String? {
        if case .hold(let reason) = self { return reason }
        return nil
    }
}

/// The auto-answer rules, pure so the answer/hold decision is unit-tested without a pane.
public enum AutoAnswerPolicy {
    /// How long a `blocked` prompt waits for the user before the app answers it.
    public static let defaultDelaySeconds = 45
    public static let delayRange = 5...600

    /// `screen` is the pane's visible text at fire time; `agent` the CLI the pane runs. Only the open dialog
    /// (`AutoAnswerAgent.dialogRegion`) is scanned for destructive text — with the whole screen as the
    /// fallback, so an unrecognized layout still holds rather than answers.
    public static func decide(screen: String?, agent: AutoAnswerAgent?) -> AutoAnswerDecision {
        guard let agent else { return .hold(reason: "unknown agent") }
        guard let screen else { return .hold(reason: "pane not readable") }
        let lower = screen.lowercased()
        guard agent.promptMarkers.contains(where: { lower.contains($0) }) else {
            return .hold(reason: "no prompt visible")
        }
        if let hit = DestructiveCommand.match(in: agent.dialogRegion(of: screen)) {
            return .hold(reason: "destructive: \(hit.name)")
        }
        return .answer(keys: agent.affirmativeKeys)
    }
}

/// The user-presence half of the rule: the app answers FOR the user, never OVER them. A prompt in a session
/// the user is not looking at is answered once the grace has run; one in the session on screen in the
/// frontmost window is deferred while the user is moving (a keystroke or a selection anywhere in that
/// window inside the grace) — they are reading, and the countdown restarts from their last move.
public enum AutoAnswerPresence {
    /// Seconds still owed to the user before the grace may fire; 0 fires now. `idle` is the window's time
    /// since the last user input, nil when there was none this run.
    public static func remainingGrace(delay: TimeInterval, userInSession: Bool, idle: TimeInterval?) -> TimeInterval {
        guard userInSession, let idle else { return 0 }
        return max(0, delay - idle)
    }
}

/// The countdown panel shown over a blocked session while its grace runs, so a user who is (or arrives)
/// in the session sees what is about to happen and that any key keeps the prompt for them.
public enum AutoAnswerHud {
    public static let messagePrefix = "Auto-answer in "

    public static func spec(remaining: TimeInterval, agent: AutoAnswerAgent?) -> HudSpec {
        let key = agent == .codex ? "y" : "Return"
        return HudSpec(message: messagePrefix + "\(max(0, Int(remaining.rounded(.up)))) s",
                       detail: "Nobody answered this prompt. The app will press \(key) — any key here keeps it for you.",
                       position: .topRight)
    }

    /// Whether a live HUD is this feature's own, so closing it can never take down a caller's panel.
    public static func owns(_ spec: HudSpec?) -> Bool {
        spec?.message.hasPrefix(messagePrefix) == true
    }
}

/// Per-session auto-answer memory, ephemeral: the session's own on/off override, whether a grace is
/// running, and what the last decision was.
public struct AutoAnswerState: Equatable, Sendable {
    /// nil = follow Settings; `session autoanswer on|off` sets it for this session only.
    public var enabledOverride: Bool?
    /// The instant the running grace fires, nil when none is pending.
    public var dueAt: Date?
    public var answered = 0
    public var held = 0
    public var lastAction: String?
    public var lastReason: String?
    public var lastAt: Date?

    public init() {}

    public func effectiveEnabled(settings: Bool) -> Bool { enabledOverride ?? settings }

    public mutating func record(_ decision: AutoAnswerDecision, at now: Date = Date()) {
        dueAt = nil
        switch decision {
        case .answer: answered += 1
        case .hold: held += 1
        }
        lastAction = decision.name
        lastReason = decision.reason
        lastAt = now
    }
}

/// The read side of `session.autoanswer`: on the session's tree node, in the command's result and in the
/// status answer.
public struct ControlAutoAnswerNode: Codable, Sendable, Equatable {
    public let enabled: Bool
    /// `session` when `session autoanswer on|off` set it, `settings` otherwise.
    public let source: String
    public let delaySeconds: Int
    /// ISO 8601 with the local offset while a grace is running; omitted otherwise.
    public let dueAt: String?
    public let answered: Int?
    public let held: Int?
    public let lastAction: String?
    public let lastReason: String?

    public init(enabled: Bool, source: String, delaySeconds: Int, dueAt: String? = nil, answered: Int? = nil,
                held: Int? = nil, lastAction: String? = nil, lastReason: String? = nil) {
        self.enabled = enabled
        self.source = source
        self.delaySeconds = delaySeconds
        self.dueAt = dueAt
        self.answered = answered
        self.held = held
        self.lastAction = lastAction
        self.lastReason = lastReason
    }

    /// Unlike `ControlFailoverNode.project`, never nil: the enabled/delay pair is meaningful before anything
    /// happened. Counters are omitted while zero to keep the node compact.
    public static func project(_ state: AutoAnswerState, settingsEnabled: Bool, delaySeconds: Int) -> ControlAutoAnswerNode {
        ControlAutoAnswerNode(enabled: state.effectiveEnabled(settings: settingsEnabled),
                              source: state.enabledOverride == nil ? "settings" : "session",
                              delaySeconds: delaySeconds,
                              dueAt: state.dueAt.map { ControlISO8601.string($0) },
                              answered: state.answered > 0 ? state.answered : nil,
                              held: state.held > 0 ? state.held : nil,
                              lastAction: state.lastAction, lastReason: state.lastReason)
    }
}

/// What `session.autoanswer` carries into the host after the dispatcher validated it.
public struct ControlAutoAnswerOptions: Equatable, Sendable {
    public let window: String?
    /// nil = `status` (read only); true/false = set the session's override.
    public let enable: Bool?

    public init(window: String?, enable: Bool?) {
        self.window = window
        self.enable = enable
    }
}
