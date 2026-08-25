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
}

/// A local agent CLI agterm knows how to offer: found on `PATH`, it becomes a one-click "connect" row
/// in Settings ▸ Agents. The catalog is a convenience for discovery only — a user can always add an
/// arbitrary command, and an agent already connected keeps working when its binary later disappears.
public struct KnownAgent: Sendable, Equatable, Identifiable {
    /// The binary name, which is also the stable identity (`claude`, `codex`, …).
    public var id: String { binary }
    public let name: String
    public let binary: String
    /// The launch line seeded into the new `AgentDefinition`; usually just the binary.
    public let command: String

    public init(name: String, binary: String, command: String? = nil) {
        self.name = name
        self.binary = binary
        self.command = command ?? binary
    }
}

/// Discovery of local agent CLIs. Host-free: the filesystem probe is injected, so the resolution order
/// is unit-testable without touching a real `PATH`.
public enum AgentCatalog {
    /// The agents offered on the Settings ▸ Agents "available" list, in the order they are shown.
    /// A binary missing from `PATH` is simply not offered; nothing here is required to exist.
    public static let known: [KnownAgent] = [
        KnownAgent(name: "Claude Code", binary: "claude"),
        KnownAgent(name: "Codex", binary: "codex"),
        KnownAgent(name: "Gemini CLI", binary: "gemini"),
        KnownAgent(name: "Copilot CLI", binary: "copilot"),
        KnownAgent(name: "Cursor Agent", binary: "cursor-agent"),
        KnownAgent(name: "OpenCode", binary: "opencode"),
        KnownAgent(name: "Crush", binary: "crush"),
        KnownAgent(name: "Aider", binary: "aider"),
        KnownAgent(name: "Amp", binary: "amp"),
        KnownAgent(name: "Goose", binary: "goose"),
        KnownAgent(name: "Kimi Code", binary: "kimi"),
        KnownAgent(name: "Qwen Code", binary: "qwen"),
        KnownAgent(name: "Droid", binary: "droid"),
        KnownAgent(name: "Mimo", binary: "mimo"),
        KnownAgent(name: "Hermes", binary: "hermes"),
    ]

    /// The known agents whose binary is executable somewhere on `searchPath` (a colon-joined `PATH`),
    /// in catalog order. `isExecutable` is injected for tests; `detectInstalled()` passes the real one.
    public static func detect(searchPath: String, isExecutable: (String) -> Bool) -> [KnownAgent] {
        let dirs = searchPath.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        return known.filter { agent in
            dirs.contains { isExecutable(($0 as NSString).appendingPathComponent(agent.binary)) }
        }
    }

    /// The known agents installed on this machine. The GUI runs under launchd, whose `PATH` omits the
    /// per-user tool dirs agents actually install into (`~/.local/bin`, `~/.bun/bin`, Homebrew), so the
    /// probe searches the process `PATH` PLUS those, rather than trusting the inherited one.
    public static func detectInstalled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: String = NSHomeDirectory()) -> [KnownAgent] {
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
