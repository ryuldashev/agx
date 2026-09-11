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
/// argument either right after the launch line or behind a flag (`seedFlag` in the manifest).
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

/// One lifecycle hook an agent's JSON hook file runs: the event, an optional matcher, the script
/// (relative to the installed package directory) and its arguments, quoted at install time.
public struct HookBinding: Codable, Equatable, Sendable {
    public let event: String
    public let matcher: String?
    public let script: String
    public let args: [String]

    public init(event: String, matcher: String? = nil, script: String, args: [String] = []) {
        self.event = event
        self.matcher = matcher
        self.script = script
        self.args = args
    }
}

/// The JSON hook-file dialects the installer can merge into.
public enum HookDialect: String, Codable, Sendable {
    /// `hooks.<Event>: [{matcher?, hooks: [{type: command, command}]}]` — Claude Code, Gemini CLI.
    case claude
    /// `{version: 1, hooks: {<event>: [{command}]}}` — Cursor's `hooks.json`; no matchers.
    case cursor
}

/// One `[[hooks.<event>]]` row of a TOML hook file: the agent's event and the action word the agent's
/// adapter script receives as `$1`.
public struct TOMLHookEvent: Codable, Equatable, Sendable {
    public let event: String
    public let action: String

    public init(event: String, action: String) {
        self.event = event
        self.action = action
    }
}

/// How the agent-status indicator learns what an agent is doing — the `status` object of a manifest,
/// discriminated by `kind`. The core knows these three mechanisms and nothing about any agent.
public enum StatusIntegration: Equatable, Sendable {
    /// Hooks merged into a JSON hook file (`file` relative to `~`).
    case jsonHooks(file: String, dialect: HookDialect, hooks: [HookBinding])
    /// A marker-guarded `[[hooks.*]]` block in a TOML config (`file` relative to `~`) invoking the
    /// agent's adapter `script` (relative to the package) with one `action` per event.
    case tomlHooks(file: String, script: String, events: [TOMLHookEvent])
    /// A bundled plugin `source` (relative to the package) copied to `destination` (relative to `~`)
    /// once `requires` (relative to `~`) exists; `marker` is the ownership sentinel a reinstall needs
    /// before overwriting an existing file.
    case plugin(source: String, destination: String, requires: String, marker: String)
    /// Nothing to install: the pane shows no status glyph for this agent.
    case none
}

/// How `agx context` reaches a fresh agent so it knows the UI it lives in.
public enum ContextDelivery: String, Codable, Sendable {
    /// A session-start hook returns it as additional context — the brief stays clean.
    case sessionStartHook
    /// No hook surface: `agx spawn` prefixes the brief with a one-line pointer to `agx context`.
    case briefPrefix
}

/// Everything agx knows about one agent CLI, decoded from `agents/<binary>/agent.json` in the
/// agent-status package. The manifests are the single source of that knowledge: the installer, the
/// seed line, the restore pin and `agx spawn` (python, same files) all read them, and no other code
/// names an agent. A manifest with only `name` and `binary` is launch-only — seeded positionally, no
/// status, no resume — the graceful floor for a CLI agx has not studied yet. Measured facts per agent
/// live in `docs/reference/agents/<binary>.md`.
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
    /// The agent's own post-install step (`status.activate`), shown after a successful install — "Run
    /// /hooks in Codex to approve them", "Restart Pi or run /reload" — nil when nothing needs doing.
    public let activate: String?
    public let context: ContextDelivery
    /// The agent's config directory relative to `~` (`.claude`); its presence gates the installer.
    public let configDirectory: String?
    /// Position on the Settings ▸ Agents "available" list; unlisted manifests sort last, by binary.
    public let order: Int

    public init(name: String, binary: String, command: String? = nil, seed: BriefSeed = .positional,
                resumeTemplate: String? = nil, status: StatusIntegration = .none, activate: String? = nil,
                context: ContextDelivery = .briefPrefix, configDirectory: String? = nil, order: Int = .max) {
        self.name = name
        self.binary = binary
        self.command = command ?? binary
        self.seed = seed
        self.resumeTemplate = resumeTemplate
        self.status = status
        self.activate = activate
        self.context = context
        self.configDirectory = configDirectory
        self.order = order
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

    /// The `hooks` bindings when status rides a JSON hook file, empty otherwise.
    public var jsonHookBindings: [HookBinding] {
        if case .jsonHooks(_, _, let hooks) = status { return hooks }
        return []
    }

    /// The JSON hook file (relative to `~`) the bindings merge into, nil for other integrations.
    public var jsonHooksFile: String? {
        if case .jsonHooks(let file, _, _) = status { return file }
        return nil
    }

    public var jsonHooksDialect: HookDialect? {
        if case .jsonHooks(_, let dialect, _) = status { return dialect }
        return nil
    }
}

extension AgentProfile: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, binary, command, seedFlag, resume, status, context, configDirectory, order
    }

    private struct Status: Decodable {
        enum Kind: String, Decodable { case jsonHooks, tomlHooks, plugin }
        let kind: Kind
        let activate: String?
        let file: String?
        let dialect: HookDialect?
        let hooks: [HookBinding]?
        let script: String?
        let events: [TOMLHookEvent]?
        let source: String?
        let destination: String?
        let requires: String?
        let marker: String?

        func integration(_ decoder: Decoder) throws -> StatusIntegration {
            func need<T>(_ value: T?, _ key: String) throws -> T {
                guard let value else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                            debugDescription: "status.\(key) missing for \(kind)"))
                }
                return value
            }
            switch kind {
            case .jsonHooks:
                return .jsonHooks(file: try need(file, "file"), dialect: try need(dialect, "dialect"),
                                  hooks: try need(hooks, "hooks"))
            case .tomlHooks:
                return .tomlHooks(file: try need(file, "file"), script: try need(script, "script"),
                                  events: try need(events, "events"))
            case .plugin:
                return .plugin(source: try need(source, "source"), destination: try need(destination, "destination"),
                               requires: try need(requires, "requires"), marker: try need(marker, "marker"))
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let status = try c.decodeIfPresent(Status.self, forKey: .status)
        self.init(name: try c.decode(String.self, forKey: .name),
                  binary: try c.decode(String.self, forKey: .binary),
                  command: try c.decodeIfPresent(String.self, forKey: .command),
                  seed: try c.decodeIfPresent(String.self, forKey: .seedFlag).map(BriefSeed.flag) ?? .positional,
                  resumeTemplate: try c.decodeIfPresent(String.self, forKey: .resume),
                  status: try status?.integration(decoder) ?? .none,
                  activate: status?.activate,
                  context: try c.decodeIfPresent(ContextDelivery.self, forKey: .context) ?? .briefPrefix,
                  configDirectory: try c.decodeIfPresent(String.self, forKey: .configDirectory),
                  order: try c.decodeIfPresent(Int.self, forKey: .order) ?? .max)
    }
}

/// The agent manifests and discovery of local agent CLIs. Host-free: the filesystem probe is injected,
/// so the resolution order is unit-testable without touching a real `PATH`.
public enum AgentCatalog {
    /// The manifests directory inside an agent-status package.
    public static let agentsDirectoryName = "agents"
    public static let manifestName = "agent.json"

    /// Every agent with a manifest, in `order`. Resolved once: `AGTERM_AGENTS_DIR`, else the bundled
    /// package's `agents/` (the app and its `agtermctl`), else the source checkout's (`swift test`).
    /// No directory at all → empty, and every launch line is treated as an unknown, launch-only agent.
    public static let known: [AgentProfile] = load(directory: defaultDirectory)

    /// Decode every `<directory>/<x>/agent.json`, skipping a malformed one so a single bad manifest
    /// cannot take the whole catalog down (`AgentCatalogTests` asserts the bundled set decodes).
    public static func load(directory: URL?) -> [AgentProfile] {
        guard let directory,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        let profiles = entries.compactMap { entry -> AgentProfile? in
            guard let data = try? Data(contentsOf: entry.appendingPathComponent(manifestName)) else { return nil }
            return try? decoder.decode(AgentProfile.self, from: data)
        }
        return profiles.sorted { ($0.order, $0.binary) < ($1.order, $1.binary) }
    }

    static var defaultDirectory: URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["AGTERM_AGENTS_DIR"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("agent-status/\(agentsDirectoryName)"))
        }
        candidates.append(sourceDirectory)
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    /// `agterm/Resources/agent-status/agents` relative to this source file — the SPM test run, which
    /// has no app bundle.
    static var sourceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("agterm/Resources/agent-status/\(agentsDirectoryName)")
    }

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
