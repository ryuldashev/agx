import Foundation

/// One agent the user has connected: a display name and the shell line that launches it. Stored in
/// `AppSettings.agents` (so it rides `settings.json`, not the per-window tree) and referenced by
/// `Workspace.defaultAgentID`, so renaming or re-pointing an agent updates every workspace at once.
public struct AgentDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Row label in Settings and in the workspace picker.
    public var name: String
    /// The shell line run as the session's process (`session new --command`), e.g. `claude` or
    /// `claude --resume`. Stored verbatim; a blank command makes the agent inert (a plain shell).
    public var command: String

    public init(id: UUID = UUID(), name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }

    /// The launch line, or nil when blank — the single read point, so a hand-edited `"command": " "`
    /// in `settings.json` opens a normal shell instead of running whitespace.
    public var launchCommand: String? { command.trimmedOrNil }

    /// The catalog profile behind this launch line, nil for a command naming no known agent.
    public var profile: AgentProfile? { AgentCatalog.profile(forCommandLine: command) }
}

/// How an agent CLI takes the brief a spawn or scheduled job hands it: the text becomes ONE shell
/// argument either right after the launch line or behind a flag.
public enum BriefSeed: Equatable, Sendable {
    /// `<agent> "<brief>"` — Claude Code, Codex, most TUIs.
    case positional
    /// `<agent> <flag> "<brief>"` — Gemini CLI's `-i`, OpenCode's `--prompt` (their positional means
    /// something else: headless mode, a project directory).
    case flag(String)

    /// The argument list appended to the launch line, `briefArgument` already shell-quoted.
    public func arguments(briefArgument: String) -> String {
        switch self {
        case .positional: return briefArgument
        case .flag(let flag): return flag + " " + briefArgument
        }
    }
}

/// One lifecycle hook an agent's JSON `settings.json` runs: the event, an optional matcher, the script
/// (relative to the installed script directory) and its arguments. Claude Code and Gemini CLI share
/// this shape byte-for-byte (`hooks.<Event>: [{matcher?, hooks: [{type: command, command}]}]`).
public struct HookBinding: Equatable, Sendable {
    public let event: String
    public let matcher: String?
    public let script: String
    public let args: String

    public init(event: String, matcher: String? = nil, script: String, args: String = "") {
        self.event = event
        self.matcher = matcher
        self.script = script
        self.args = args
    }
}

/// The two JSON hook-file dialects agx can merge into.
public enum HookFileShape: Equatable, Sendable {
    /// `hooks.<Event>: [{matcher?, hooks: [{type: command, command}]}]` — Claude Code, Gemini CLI.
    case claude
    /// `{version: 1, hooks: {<event>: [{command}]}}` — Cursor's `hooks.json`; no matchers.
    case cursor
}

/// How the agent-status indicator learns what an agent is doing.
public enum StatusIntegration: Equatable, Sendable {
    /// Lifecycle hooks merged into a JSON hook file (relative to `~`).
    case jsonHooks(settingsFile: String, shape: HookFileShape, hooks: [HookBinding])
    /// Codex's `[[hooks.*]]` array-of-tables in `config.toml`, driven by the bundled Codex adapter.
    case codexConfig
    /// Pi's auto-discovered global extension.
    case piExtension
    /// OpenCode's auto-discovered global plugin.
    case opencodePlugin
    /// Nothing to install: the pane shows no status glyph for this agent.
    case none
}

/// How `agx context` reaches a fresh agent so it knows the UI it lives in.
public enum ContextDelivery: Equatable, Sendable {
    /// A `SessionStart` hook returns it as `additionalContext` — the brief stays clean.
    case sessionStartHook
    /// No hook surface: `agx spawn` prefixes the brief with a one-line pointer to `agx context`.
    case briefPrefix
}

/// Everything agx knows about one agent CLI. The catalog is the single source of that knowledge: the
/// installer, the seed line, the restore pin and `agx spawn` all read it, and no other code names an
/// agent. A profile with only `name` and `binary` is launch-only — seeded positionally, no status, no
/// resume — the graceful floor for a CLI agx has not studied yet. Measured facts per agent live in
/// `docs/reference/agents/<binary>.md`.
public struct AgentProfile: Sendable, Equatable, Identifiable {
    /// The binary name, which is also the stable identity (`claude`, `codex`, …).
    public var id: String { binary }
    public let name: String
    public let binary: String
    /// The launch line seeded into a new `AgentDefinition`; usually just the binary.
    public let command: String
    public let seed: BriefSeed
    /// The launch line that reopens a session by id (`{id}` substituted), nil when the CLI cannot.
    public let resumeTemplate: String?
    public let status: StatusIntegration
    public let context: ContextDelivery
    /// The agent's config directory relative to `~` (`.claude`); its presence gates the installer.
    public let configDirectory: String?

    public init(name: String, binary: String, command: String? = nil, seed: BriefSeed = .positional,
                resumeTemplate: String? = nil, status: StatusIntegration = .none,
                context: ContextDelivery = .briefPrefix, configDirectory: String? = nil) {
        self.name = name
        self.binary = binary
        self.command = command ?? binary
        self.seed = seed
        self.resumeTemplate = resumeTemplate
        self.status = status
        self.context = context
        self.configDirectory = configDirectory
    }

    /// The restore line for `sessionID`, nil when the agent has no resume or the id is not id-shaped
    /// (it lands inside a shell line, so anything else is refused rather than quoted).
    public func resumeCommand(sessionID: String) -> String? {
        guard let resumeTemplate, !sessionID.isEmpty,
              sessionID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return resumeTemplate.replacingOccurrences(of: "{id}", with: sessionID)
    }

    public var supportsResume: Bool { resumeTemplate != nil }

    public var hasStatusIntegration: Bool {
        if case .none = status { return false }
        return true
    }

    /// The `hooks` bindings when status rides a JSON settings file, empty otherwise.
    public var jsonHookBindings: [HookBinding] {
        if case .jsonHooks(_, _, let hooks) = status { return hooks }
        return []
    }

    /// The JSON hook file (relative to `~`) the bindings merge into, nil for other integrations.
    public var jsonHooksSettingsFile: String? {
        if case .jsonHooks(let file, _, _) = status { return file }
        return nil
    }

    public var jsonHooksShape: HookFileShape? {
        if case .jsonHooks(_, let shape, _) = status { return shape }
        return nil
    }
}

/// Discovery of local agent CLIs. Host-free: the filesystem probe is injected, so the resolution order
/// is unit-testable without touching a real `PATH`.
public enum AgentCatalog {
    /// The four status hooks share `agterm-agent-status.sh` and differ by state; `prompt` and `afterTool`
    /// both set `active` — the latter so the status returns to `active` when work RESUMES after a
    /// `blocked` permission prompt (no agent has a "permission answered" event, and the gated tool's
    /// pre-hook fired BEFORE `blocked` was set). Only `stop`→`completed` auto-resets. The two
    /// `SessionStart` entries pin the restore line and feed `agx context`; restore comes first so the
    /// pin lands before the (slower) context call.
    static func statusHooks(prompt: String, afterTool: String, stop: String,
                            permission: (event: String, matcher: String)?, sessionStart: String = "SessionStart",
                            resumeTemplate: String, contextFormat: String = "claude") -> [HookBinding] {
        var hooks = [
            HookBinding(event: prompt, script: AgentHooksInstall.wrapperName, args: " active --blink"),
            HookBinding(event: afterTool, script: AgentHooksInstall.wrapperName, args: " active --blink"),
            HookBinding(event: stop, script: AgentHooksInstall.wrapperName, args: " completed --auto-reset"),
        ]
        if let permission {
            hooks.append(HookBinding(event: permission.event, matcher: permission.matcher,
                                     script: AgentHooksInstall.wrapperName, args: " blocked"))
        }
        hooks.append(HookBinding(event: sessionStart, script: AgentHooksInstall.sessionRestoreHookName,
                                 args: " --resume-line " + AgentHooksInstall.shellQuote(resumeTemplate)))
        hooks.append(HookBinding(event: sessionStart, script: AgentHooksInstall.sessionContextHookName,
                                 args: " --format " + contextFormat))
        return hooks
    }

    /// `StopFailure` is Claude Code's alone: it reports a turn-ending API error to `session.failure`, so
    /// the app can switch model or hand the task to another agent (`AgentFailover`).
    public static let claude = AgentProfile(
        name: "Claude Code", binary: "claude",
        resumeTemplate: "claude --resume {id} --fork-session",
        status: .jsonHooks(settingsFile: ".claude/settings.json", shape: .claude, hooks: statusHooks(
            prompt: "UserPromptSubmit", afterTool: "PostToolUse", stop: "Stop",
            permission: ("Notification", "permission_prompt"),
            resumeTemplate: "claude --resume {id} --fork-session")
            + [HookBinding(event: "StopFailure", script: AgentHooksInstall.agentFailureHookName)]),
        context: .sessionStartHook, configDirectory: ".claude")

    /// Gemini CLI's hooks are a port of Claude Code's (`gemini hooks migrate` exists), renamed: there is
    /// no `Stop`, so `AfterAgent` closes a turn, and `Notification` matches on `notification_type`.
    /// `-i` seeds an interactive session — the positional argument is headless mode.
    public static let gemini = AgentProfile(
        name: "Gemini CLI", binary: "gemini", seed: .flag("-i"),
        resumeTemplate: "gemini -r {id}",
        status: .jsonHooks(settingsFile: ".gemini/settings.json", shape: .claude, hooks: statusHooks(
            prompt: "BeforeAgent", afterTool: "AfterTool", stop: "AfterAgent",
            permission: ("Notification", "ToolPermission"),
            resumeTemplate: "gemini -r {id}")),
        context: .sessionStartHook, configDirectory: ".gemini")

    public static let codex = AgentProfile(
        name: "Codex", binary: "codex",
        resumeTemplate: "codex resume {id}",
        status: .codexConfig, configDirectory: ".codex")

    /// Cursor's `hooks.json` has no permission event and no matchers; `sessionStart` answers with a
    /// top-level `additional_context` rather than Claude's envelope.
    public static let cursor = AgentProfile(
        name: "Cursor Agent", binary: "cursor-agent",
        resumeTemplate: "cursor-agent --resume {id}",
        status: .jsonHooks(settingsFile: ".cursor/hooks.json", shape: .cursor, hooks: statusHooks(
            prompt: "beforeSubmitPrompt", afterTool: "postToolUse", stop: "stop", permission: nil,
            sessionStart: "sessionStart", resumeTemplate: "cursor-agent --resume {id}", contextFormat: "cursor")),
        context: .sessionStartHook, configDirectory: ".cursor")

    /// `opencode <text>` reads the text as a project directory; the prompt rides `--prompt`.
    public static let opencode = AgentProfile(
        name: "OpenCode", binary: "opencode", seed: .flag("--prompt"),
        resumeTemplate: "opencode --session {id}",
        status: .opencodePlugin, configDirectory: ".config/opencode")

    /// Mimo Code is an OpenCode fork with the same CLI surface; its plugin loading is unverified, so
    /// status stays off until measured (`docs/reference/agents/mimo.md`).
    public static let mimo = AgentProfile(
        name: "Mimo", binary: "mimo", seed: .flag("--prompt"),
        resumeTemplate: "mimo --session {id}", configDirectory: ".config/mimocode")

    /// The agents offered on the Settings ▸ Agents "available" list, in the order they are shown.
    /// A binary missing from `PATH` is simply not offered; nothing here is required to exist.
    public static let known: [AgentProfile] = [
        claude,
        codex,
        gemini,
        AgentProfile(name: "Copilot CLI", binary: "copilot"),
        cursor,
        opencode,
        AgentProfile(name: "Crush", binary: "crush"),
        AgentProfile(name: "Aider", binary: "aider"),
        AgentProfile(name: "Amp", binary: "amp"),
        AgentProfile(name: "Goose", binary: "goose"),
        AgentProfile(name: "Kimi Code", binary: "kimi"),
        AgentProfile(name: "Qwen Code", binary: "qwen"),
        AgentProfile(name: "Droid", binary: "droid"),
        mimo,
        AgentProfile(name: "Hermes", binary: "hermes"),
        AgentProfile(name: "Pi", binary: "pi", status: .piExtension, configDirectory: ".pi"),
    ]

    public static func profile(binary: String) -> AgentProfile? {
        known.first { $0.binary == binary }
    }

    /// The profile of the first token in a launch or restore line that names a known agent
    /// (`exec claude "$b"`, `claude --resume …`, `codex --model x`), nil when none does.
    public static func profile(forCommandLine commandLine: String?) -> AgentProfile? {
        guard let commandLine else { return nil }
        let tokens = commandLine.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "'" || $0 == "\"" })
        for token in tokens {
            let base = token.split(separator: "/").last.map(String.init) ?? String(token)
            if let hit = profile(binary: base) { return hit }
        }
        return nil
    }

    /// The known agents whose binary is executable somewhere on `searchPath` (a colon-joined `PATH`),
    /// in catalog order. `isExecutable` is injected for tests; `detectInstalled()` passes the real one.
    public static func detect(searchPath: String, isExecutable: (String) -> Bool) -> [AgentProfile] {
        let dirs = searchPath.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        return known.filter { agent in
            dirs.contains { isExecutable(($0 as NSString).appendingPathComponent(agent.binary)) }
        }
    }

    /// The known agents installed on this machine. The GUI runs under launchd, whose `PATH` omits the
    /// per-user tool dirs agents actually install into (`~/.local/bin`, `~/.bun/bin`, Homebrew), so the
    /// probe searches the process `PATH` PLUS those, rather than trusting the inherited one.
    public static func detectInstalled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: String = NSHomeDirectory()) -> [AgentProfile] {
        let manager = FileManager.default
        return detect(searchPath: searchPath(environment: environment, home: home)) {
            manager.isExecutableFile(atPath: $0)
        }
    }

    /// The `PATH` used for detection: the inherited one first (a user's own ordering wins), then the
    /// common per-user install dirs a launchd-spawned GUI never sees. Duplicates are dropped so a large
    /// `PATH` doesn't multiply the stat calls.
    public static func searchPath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: String = NSHomeDirectory()) -> String {
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + ["/.local/bin", "/.bun/bin", "/.cargo/bin", "/bin", "/.npm-global/bin"].map { home + $0 }
        var seen = Set<String>()
        let all = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + extras
        return all.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }
}
