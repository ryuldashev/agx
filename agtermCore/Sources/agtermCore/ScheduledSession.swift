import Foundation

/// A session the app will create at a later time and hand a brief as the agent's first message. Persisted
/// so a job survives a relaunch; the app is the long-lived process, so no launchd or cron is involved.
public struct ScheduledSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var fireAt: Date
    /// The task text handed to the agent on its command line, never typed into a TUI.
    public var brief: String
    public var name: String?
    /// The window whose store held the workspace when the job was added; the fire falls back to the
    /// frontmost store when it is no longer open.
    public var windowID: UUID?
    public var workspaceID: UUID?
    /// Kept beside the id so a workspace deleted before the fire is recreated by name rather than lost.
    public var workspaceName: String?
    public var cwd: String?
    /// The launch line, resolved at add time from `--command` or `--agent`. Nil = the workspace's default
    /// agent at fire time, else `ScheduledLaunch.fallbackAgent`.
    public var launch: String?
    public var foreground: Bool
    /// Set when the job was found overdue past `SchedulePolicy.missedGrace`; it stays listed for a manual
    /// `schedule.run` or `schedule.cancel` instead of firing a stale brief on its own.
    public var missedAt: Date?

    public init(id: UUID = UUID(), createdAt: Date = Date(), fireAt: Date, brief: String, name: String? = nil,
                windowID: UUID? = nil, workspaceID: UUID? = nil, workspaceName: String? = nil,
                cwd: String? = nil, launch: String? = nil, foreground: Bool = true, missedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.fireAt = fireAt
        self.brief = brief
        self.name = name
        self.windowID = windowID
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.cwd = cwd
        self.launch = launch
        self.foreground = foreground
        self.missedAt = missedAt
    }

    public var isMissed: Bool { missedAt != nil }
}

/// The persisted form: one file per state directory, version-gated like `Snapshot`.
public struct ScheduledSessionsFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var items: [ScheduledSession]

    public init(version: Int = ScheduledSessionsFile.currentVersion, items: [ScheduledSession] = []) {
        self.version = version
        self.items = items
    }
}

/// JSON load/save of the scheduled list at `<stateDirectory>/scheduled.json`, plus the per-job brief
/// files under `<stateDirectory>/scheduled/`. Same recovery contract as `PersistenceStore`: a missing,
/// corrupt, or foreign-version file loads as empty, and saves are atomic.
public struct ScheduleStore: Sendable {
    public static let fileName = "scheduled.json"
    public static let briefDirectoryName = "scheduled"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    private var briefDirectory: URL { directory.appendingPathComponent(Self.briefDirectoryName, isDirectory: true) }

    public func load() -> [ScheduledSession] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? Self.decoder.decode(ScheduledSessionsFile.self, from: data),
              file.version == ScheduledSessionsFile.currentVersion else { return [] }
        return file.items
    }

    public func save(_ items: [ScheduledSession]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ScheduledSessionsFile(items: items))
        try data.write(to: fileURL, options: .atomic)
    }

    public func briefFile(for id: UUID) -> String {
        briefDirectory.appendingPathComponent("\(id.uuidString).brief").path
    }

    public func writeBrief(_ item: ScheduledSession) throws {
        try FileManager.default.createDirectory(at: briefDirectory, withIntermediateDirectories: true)
        try Data(item.brief.utf8).write(to: URL(fileURLWithPath: briefFile(for: item.id)), options: .atomic)
    }

    public func removeBrief(for id: UUID) {
        try? FileManager.default.removeItem(atPath: briefFile(for: id))
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// When a job runs relative to now. Pure, so the timer arming and the launch-time sweep share one rule.
public enum SchedulePolicy {
    /// How long past `fireAt` a job still fires on its own. Beyond it the brief is stale — a session for
    /// "tomorrow morning" opened three days later would only burn an agent turn — so it parks as missed.
    public static let missedGrace: TimeInterval = 24 * 60 * 60

    public enum Decision: Equatable, Sendable {
        case wait
        case fire
        case missed
    }

    public static func decide(_ item: ScheduledSession, now: Date) -> Decision {
        if item.isMissed { return .missed }
        if item.fireAt > now { return .wait }
        return now.timeIntervalSince(item.fireAt) <= missedGrace ? .fire : .missed
    }

    /// The earliest pending fire time, nil when nothing is waiting. Missed jobs never arm a timer.
    public static func nextFire(in items: [ScheduledSession], now: Date) -> Date? {
        items.filter { decide($0, now: now) == .wait }.map(\.fireAt).min()
    }
}

/// The shell line a fired job runs: the agent gets the brief as ONE argument read from a file the line
/// then deletes, so quotes, newlines, and `$` in the brief never reach the shell as syntax. The same
/// shape `agx spawn` used before the feature moved into the app.
public enum ScheduledLaunch {
    public static let fallbackAgent = "claude"

    public static func commandLine(launch: String?, briefFile: String) -> String {
        let agent = launch.trimmedOrNilValue ?? fallbackAgent
        let body = "b=\"$(cat \(quote(briefFile)))\"; rm -f \(quote(briefFile)); exec \(agent) \"$b\""
        return "/bin/zsh -lc \(quote(body))"
    }

    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Parses the `--at` argument. Accepted forms, all resolved in `calendar`'s time zone:
/// `+90s|+30m|+2h|+1d`; `HH:MM` (today, or tomorrow when already past); `tomorrow [HH:MM]` (09:00 when
/// omitted); `YYYY-MM-DD [HH:MM]` (09:00 when omitted); ISO 8601 `YYYY-MM-DDTHH:MM[:SS][Z|±HH:MM]`
/// (no zone = local). Nil for anything else.
public enum ScheduleTime {
    public static let acceptedForms = "+30m|+2h|+1d, HH:MM, tomorrow [HH:MM], YYYY-MM-DD [HH:MM], or ISO 8601"
    public static let defaultHour = 9

    public static func parse(_ raw: String, now: Date, calendar: Calendar = .current) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("+") { return relative(String(text.dropFirst()), now: now) }
        if text.hasPrefix("tomorrow") {
            let rest = text.dropFirst("tomorrow".count).trimmingCharacters(in: .whitespaces)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return at(day: tomorrow, time: rest.isEmpty ? (defaultHour, 0) : clock(rest), calendar: calendar)
        }
        if let time = clock(text) {
            guard let today = at(day: calendar.startOfDay(for: now), time: time, calendar: calendar) else { return nil }
            if today > now { return today }
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        if let iso = isoDate(text, calendar: calendar) { return iso }
        return dayAndTime(text, calendar: calendar)
    }

    private static func relative(_ text: String, now: Date) -> Date? {
        guard let unit = text.last, let amount = Double(text.dropLast()), amount > 0 else { return nil }
        let seconds: Double
        switch unit {
        case "s": seconds = amount
        case "m": seconds = amount * 60
        case "h": seconds = amount * 3600
        case "d": seconds = amount * 86_400
        default: return nil
        }
        return now.addingTimeInterval(seconds)
    }

    private static func clock(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func at(day: Date, time: (Int, Int)?, calendar: Calendar) -> Date? {
        guard let time else { return nil }
        return calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day)
    }

    private static func dayAndTime(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard (1...2).contains(parts.count), let day = calendarDay(parts[0], calendar: calendar) else { return nil }
        return at(day: day, time: parts.count == 2 ? clock(parts[1]) : (defaultHour, 0), calendar: calendar)
    }

    private static func calendarDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    private static func isoDate(_ text: String, calendar: Calendar) -> Date? {
        guard text.contains("t") else { return nil }
        let upper = text.uppercased()
        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime]
        if let date = zoned.date(from: upper) { return date }
        zoned.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = zoned.date(from: upper) { return date }
        // no zone: local. ISO8601DateFormatter insists on one, so split the day from the clock by hand.
        let halves = upper.split(separator: "T", maxSplits: 1).map(String.init)
        guard halves.count == 2, let day = calendarDay(halves[0], calendar: calendar) else { return nil }
        let clockParts = halves[1].split(separator: ":").map(String.init)
        guard (2...3).contains(clockParts.count), let hour = Int(clockParts[0]), let minute = Int(clockParts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let second = clockParts.count == 3 ? Int(clockParts[2]) ?? 0 : 0
        guard (0...59).contains(second) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)
    }
}

/// What `schedule.add` carries into the host after the dispatcher validated it: the parsed time and the
/// still-unresolved workspace/agent references, which need the store and settings.
public struct ControlScheduleAddOptions: Equatable, Sendable {
    public let window: String?
    public let fireAt: Date
    public let brief: String
    public let name: String?
    public let workspace: String?
    public let workspaceName: String?
    public let cwd: String?
    public let agent: String?
    public let command: String?
    public let foreground: Bool

    public init(window: String?, fireAt: Date, brief: String, name: String?, workspace: String?,
                workspaceName: String?, cwd: String?, agent: String?, command: String?, foreground: Bool) {
        self.window = window
        self.fireAt = fireAt
        self.brief = brief
        self.name = name
        self.workspace = workspace
        self.workspaceName = workspaceName
        self.cwd = cwd
        self.agent = agent
        self.command = command
        self.foreground = foreground
    }
}

/// The read-back of one job, on `schedule.list`/`schedule.add` and as the tree's top-level `scheduled`.
public struct ControlScheduledNode: Codable, Sendable, Equatable {
    public let id: String
    public let name: String?
    /// ISO 8601 with the local offset, so a script can hand it straight back to `--at`.
    public let at: String
    /// Seconds until the fire; negative once overdue.
    public let inSeconds: Int
    public let state: String
    public let workspace: String?
    public let workspaceID: String?
    public let cwd: String?
    /// The launch line, or nil for the workspace's default agent.
    public let launch: String?
    public let foreground: Bool
    public let brief: String

    public init(id: String, name: String?, at: String, inSeconds: Int, state: String, workspace: String?,
                workspaceID: String?, cwd: String?, launch: String?, foreground: Bool, brief: String) {
        self.id = id
        self.name = name
        self.at = at
        self.inSeconds = inSeconds
        self.state = state
        self.workspace = workspace
        self.workspaceID = workspaceID
        self.cwd = cwd
        self.launch = launch
        self.foreground = foreground
        self.brief = brief
    }

    public static func project(_ item: ScheduledSession, now: Date, timeZone: TimeZone = .current) -> ControlScheduledNode {
        ControlScheduledNode(id: item.id.uuidString, name: item.name, at: Self.isoString(item.fireAt, timeZone: timeZone),
                             inSeconds: Int(item.fireAt.timeIntervalSince(now).rounded()),
                             state: item.isMissed ? "missed" : "pending",
                             workspace: item.workspaceName, workspaceID: item.workspaceID?.uuidString,
                             cwd: item.cwd, launch: item.launch, foreground: item.foreground, brief: item.brief)
    }

    public static func isoString(_ date: Date, timeZone: TimeZone = .current) -> String {
        ControlISO8601.string(date, timeZone: timeZone)
    }
}
