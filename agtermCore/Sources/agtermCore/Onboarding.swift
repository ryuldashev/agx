import Foundation

/// A capability the person has used at least once — the map behind "discovered N of M" on the Welcome
/// panel. Derived from the action journal, never from a "was shown" flag; the first time each fires is
/// kept locally in `<state dir>/discoveries.json` and nothing leaves the Mac.
public enum Discovery: String, CaseIterable, Codable, Sendable {
    case spawn, statusGlyph, optionHints, palette, reader, dashboard
    case split, scratch, overlay, schedule, failover, quickTerminal

    /// The six the panel lists as first moves, in order: the ones that show what agx is for.
    public static let firstMoves: [Discovery] = [.spawn, .statusGlyph, .optionHints, .palette, .reader, .dashboard]

    public var title: String {
        switch self {
        case .spawn: return "Spawn an agent with a brief"
        case .statusGlyph: return "See an agent's status in the sidebar"
        case .optionHints: return "Hold ⌥ to name every button"
        case .palette: return "Run something from the palette"
        case .reader: return "Read a document beside the shell"
        case .dashboard: return "Open the dashboard"
        case .split: return "Split a session"
        case .scratch: return "Open the scratch terminal"
        case .overlay: return "Run a command in an overlay"
        case .schedule: return "Schedule a session"
        case .failover: return "Hand a task to another agent"
        case .quickTerminal: return "Drop the quick terminal"
        }
    }

    /// How to do it, one line — the hint under an undiscovered row.
    public var hint: String {
        switch self {
        case .spawn: return "From an agent's pane: agx spawn --brief \"…\" --name \"…\""
        case .statusGlyph: return "Once the hooks are installed: ● working · ✓ done · ⛔ waiting for you"
        case .optionHints: return "Hold ⌥ alone; the panel under the title bar lists icon, name and shortcut"
        case .palette: return "⌃P lists every action; ⌘P switches sessions"
        case .reader: return "From an agent's pane: agx reader plan.md — it live-reloads as the file changes"
        case .dashboard: return "⌘⇧G tiles every live session; arrows move, ⏎ jumps"
        case .split: return "⌘D opens a second pane; ⌘⇧D splits top/bottom"
        case .scratch: return "⌘J covers the session with a third shell; ⌘J again brings it back"
        case .overlay: return "From an agent's pane: agx run \"make test\" — output and exit code come back"
        case .schedule: return "agx schedule add --at \"tomorrow 09:00\" --brief \"…\""
        case .failover: return "Happens by itself on a spent usage pool; or agtermctl session failure rate_limit --handoff"
        case .quickTerminal: return "⌃` drops a terminal over the window from anywhere"
        }
    }

    /// The guide chapter (path under `docs/guide/`, with anchor) that covers it.
    public var guide: String {
        switch self {
        case .spawn: return "agents.md#spawning-with-a-brief"
        case .statusGlyph: return "agents.md#status-glyphs-and-attention"
        case .optionHints: return "keyboard.md#-names-the-chrome"
        case .palette: return "keyboard.md#palettes"
        case .reader: return "reader.md"
        case .dashboard: return "model.md#quick-terminal-and-dashboard"
        case .split: return "model.md#split"
        case .scratch: return "model.md#scratch"
        case .overlay: return "driving.md#agx-run"
        case .schedule: return "agents.md#scheduled-sessions"
        case .failover: return "agents.md#failover"
        case .quickTerminal: return "model.md#quick-terminal-and-dashboard"
        }
    }

    /// The discoveries one journal record proves. A control request counts when it arrives, before its
    /// target is checked, so a failed `session.reader.open` still discovers the reader — the map answers
    /// "has this person reached for it", not "did it work".
    public static func matches(kind: String, fields: [String: String]) -> [Discovery] {
        switch kind {
        case "control":
            switch fields["cmd"] {
            case "session.new": return fields["via"] == "agx-spawn" ? [.spawn] : []
            case "session.status": return [.statusGlyph]
            case "quick": return [.quickTerminal]
            case "session.reader.open": return [.reader]
            case "session.overlay.open": return [.overlay]
            case "schedule.add": return [.schedule]
            default: return []
            }
        case "action":
            var found: [Discovery] = []
            if fields["source"] == "palette" { found.append(.palette) }
            if let action = fields["action"], action.contains("quick_terminal") || action.contains("quickTerminal") {
                found.append(.quickTerminal)
            }
            return found
        case "state":
            if fields["split"] == "on" { return [.split] }
            if fields["scratch"] == "on" { return [.scratch] }
            if fields["dashboard"] == "on" { return [.dashboard] }
            if fields["hints"] == "on" { return [.optionHints] }
            if fields["failover"] == "handoff" { return [.failover] }
            return []
        default:
            return []
        }
    }
}

/// `discoveries.json`: the first time each discovery fired. Unknown ids are dropped on load so a
/// downgrade never crashes on an id it does not know.
public struct DiscoveryStore: Sendable {
    public static let fileName = "discoveries.json"
    private let directory: URL

    public init(directory: URL) { self.directory = directory }

    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func load() -> [Discovery: Date] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let raw = try? decoder.decode([String: Date].self, from: data) else { return [:] }
        var map: [Discovery: Date] = [:]
        for (key, date) in raw {
            if let discovery = Discovery(rawValue: key) { map[discovery] = date }
        }
        return map
    }

    public func save(_ map: [Discovery: Date]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var raw: [String: Date] = [:]
        for (discovery, date) in map { raw[discovery.rawValue] = date }
        try encoder.encode(raw).write(to: fileURL, options: .atomic)
    }
}

/// Turns journal records into discoveries and keeps the first time of each. Observes `ActionJournal`
/// on its serial queue, so the store is written off the main thread; `onDiscover` fires there too and the
/// UI hops to main itself.
public final class DiscoveryTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [Discovery: Date]
    private let store: DiscoveryStore?
    private let now: @Sendable () -> Date
    private let onDiscover: (@Sendable (Discovery) -> Void)?

    public init(store: DiscoveryStore?, now: @escaping @Sendable () -> Date = Date.init,
                onDiscover: (@Sendable (Discovery) -> Void)? = nil) {
        self.store = store
        self.now = now
        self.onDiscover = onDiscover
        map = store?.load() ?? [:]
    }

    public var discovered: [Discovery: Date] { lock.withLock { map } }

    public var count: Int { discovered.count }

    public func isDiscovered(_ discovery: Discovery) -> Bool { discovered[discovery] != nil }

    /// Feed one journal record; every discovery it proves is recorded once.
    public func observe(kind: String, fields: [String: String]) {
        for discovery in Discovery.matches(kind: kind, fields: fields) { record(discovery) }
    }

    /// Record a discovery; returns true the first time only.
    @discardableResult
    public func record(_ discovery: Discovery) -> Bool {
        let isNew: Bool = lock.withLock {
            guard map[discovery] == nil else { return false }
            map[discovery] = now()
            try? store?.save(map)
            return true
        }
        if isNew { onDiscover?(discovery) }
        return isNew
    }

    /// Forget everything — the panel's "start over" for someone showing agx to somebody else.
    public func reset() {
        lock.withLock {
            map = [:]
            try? store?.save(map)
        }
    }

    /// Route the journal's records here; one tracker per journal.
    public func attach(to journal: ActionJournal) {
        journal.setObserver { [weak self] kind, fields in self?.observe(kind: kind, fields: fields) }
    }
}

/// The Welcome panel's setup checklist: the rows, their copy, and the completion rule. The app side
/// reads each row's real state (TCC, symlinks, hook files) and maps it onto `State`.
public enum OnboardingSetup {
    public enum Step: String, CaseIterable, Sendable {
        case notifications, toolPermissions, cli, hooks, skill, agent
    }

    public enum State: Equatable, Sendable {
        /// Done; the detail names what is in place ("Claude Code, Codex").
        case done(String?)
        /// Not yet; the detail says what is missing or what the button will write.
        case pending(String?)
        /// Never required for "setup complete": the detail summarizes what is granted.
        case optional(String)
        /// Still being read.
        case unknown

        public var isDone: Bool {
            if case .done = self { return true }
            return false
        }

        public var detail: String? {
            switch self {
            case .done(let text), .pending(let text): return text
            case .optional(let text): return text
            case .unknown: return nil
            }
        }
    }

    /// Setup is complete when every required row is done; optional rows never hold it back.
    public static func isComplete(_ states: [Step: State]) -> Bool {
        Step.allCases.allSatisfy { step in
            switch states[step] {
            case .done, .optional: return true
            case .pending, .unknown, nil: return false
            }
        }
    }

    /// Whether an installed CLI link points at THIS app's bundle — the difference between "installed" and
    /// "another agx.app's link, or a stranger's tool with the same name".
    public static func linkPointsIntoBundle(_ target: String, bundlePath: String) -> Bool {
        let bundle = bundlePath.hasSuffix("/") ? String(bundlePath.dropLast()) : bundlePath
        return target == bundle || target.hasPrefix(bundle + "/")
    }

    public static func title(_ step: Step) -> String {
        switch step {
        case .notifications: return "Notifications"
        case .toolPermissions: return "Permissions for the tools you run"
        case .cli: return "Command line tool"
        case .hooks: return "Agent status hooks"
        case .skill: return "Agent skill"
        case .agent: return "Connect an agent"
        }
    }

    /// What the row is for, and what its button writes — the honest one-liner shown while pending.
    public static func purpose(_ step: Step) -> String {
        switch step {
        case .notifications:
            return "A banner when an agent finishes or waits for you."
        case .toolPermissions:
            return "Accessibility, Screen Recording and Full Disk Access are asked in agx's name by commands in your panes; grant only what those tools need."
        case .cli:
            return "Links agtermctl and agx into /usr/local/bin so agents in a pane can drive this window."
        case .hooks:
            return "Adds hooks to each agent's own config (Claude Code, Codex, Gemini, OpenCode, Pi) so a session shows its status, "
                + "gets agx context on start and resumes after a relaunch. Existing hooks stay; a .bak is written beside each file."
        case .skill:
            return "Copies the agterm skill into ~/.claude/skills and ~/.codex/skills — the control model, in the agent's own format."
        case .agent:
            return "Settings ▸ Agents lists the agent CLIs found on this Mac; a connected one can be a workspace's default."
        }
    }

    public static func action(_ step: Step) -> String {
        switch step {
        case .notifications: return "Allow…"
        case .toolPermissions: return "Review…"
        case .cli, .hooks, .skill: return "Install…"
        case .agent: return "Open Settings…"
        }
    }
}
