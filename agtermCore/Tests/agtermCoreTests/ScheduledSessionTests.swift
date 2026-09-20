import Foundation
import Testing
@testable import agtermCore

struct ScheduledSessionTests {
    private static let zone = TimeZone(identifier: "Asia/Tashkent")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    /// 2026-09-03 00:20 Tashkent (UTC+5).
    private static let now = ISO8601DateFormatter().date(from: "2026-09-02T19:20:00Z")!

    private func local(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Self.zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }

    private func parse(_ raw: String) -> Date? {
        ScheduleTime.parse(raw, now: Self.now, calendar: Self.calendar)
    }

    @Test(arguments: [
        ("+90s", "2026-09-03 00:21:30"),
        ("+30m", "2026-09-03 00:50:00"),
        ("+2h", "2026-09-03 02:20:00"),
        ("+1d", "2026-09-04 00:20:00"),
        ("10:00", "2026-09-03 10:00:00"),
        ("00:10", "2026-09-04 00:10:00"),
        ("tomorrow", "2026-09-04 09:00:00"),
        ("tomorrow 10:30", "2026-09-04 10:30:00"),
        ("Tomorrow 07:05", "2026-09-04 07:05:00"),
        ("2026-09-10", "2026-09-10 09:00:00"),
        ("2026-09-10 18:45", "2026-09-10 18:45:00"),
        ("2026-09-10T18:45", "2026-09-10 18:45:00"),
        ("2026-09-10T18:45:30", "2026-09-10 18:45:30"),
        ("2026-09-10T13:45:00Z", "2026-09-10 18:45:00"),
        ("2026-09-10T18:45:00+05:00", "2026-09-10 18:45:00"),
    ])
    func parsesEveryAcceptedForm(raw: String, expected: String) {
        #expect(parse(raw) == local(expected))
    }

    @Test(arguments: ["", "soon", "+0m", "+5x", "25:00", "10:60", "2026-13-01", "2026-02-30", "tomorrow noon", "next week"])
    func rejectsUnparseableTimes(raw: String) {
        #expect(parse(raw) == nil)
    }

    @Test func policyWaitsFiresAndParksByGrace() {
        let now = Self.now
        let future = ScheduledSession(fireAt: now.addingTimeInterval(60), brief: "x")
        let due = ScheduledSession(fireAt: now.addingTimeInterval(-3600), brief: "x")
        let stale = ScheduledSession(fireAt: now.addingTimeInterval(-SchedulePolicy.missedGrace - 1), brief: "x")
        let parked = ScheduledSession(fireAt: now.addingTimeInterval(-60), brief: "x", missedAt: now)
        #expect(SchedulePolicy.decide(future, now: now) == .wait)
        #expect(SchedulePolicy.decide(due, now: now) == .fire)
        #expect(SchedulePolicy.decide(stale, now: now) == .missed)
        #expect(SchedulePolicy.decide(parked, now: now) == .missed)
        #expect(SchedulePolicy.nextFire(in: [future, due, stale, parked], now: now) == future.fireAt)
        #expect(SchedulePolicy.nextFire(in: [due, parked], now: now) == nil)
    }

    @Test func storeRoundTripsAndRecoversEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(directory: directory)
        #expect(store.load().isEmpty)

        let item = ScheduledSession(fireAt: Self.now, brief: "read the plan\nthen act", name: "Spend",
                                    windowID: UUID(), workspaceID: UUID(), workspaceName: "mmee",
                                    cwd: "/tmp", launch: "claude", foreground: false)
        try store.save([item])
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == item.id)
        #expect(loaded.first?.brief == item.brief)
        #expect(loaded.first?.workspaceName == "mmee")
        #expect(loaded.first?.foreground == false)
        #expect(abs((loaded.first?.fireAt.timeIntervalSince(item.fireAt)) ?? 1) < 1)

        try Data("{\"version\": 99, \"items\": []}".utf8).write(to: directory.appendingPathComponent(ScheduleStore.fileName))
        #expect(store.load().isEmpty)
        try Data("not json".utf8).write(to: directory.appendingPathComponent(ScheduleStore.fileName))
        #expect(store.load().isEmpty)
    }

    @Test func storeWritesAndRemovesBriefFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("schedule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScheduleStore(directory: directory)
        let item = ScheduledSession(fireAt: Self.now, brief: "it's \"quoted\" $HOME")
        try store.writeBrief(item)
        let path = store.briefFile(for: item.id)
        #expect(FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) } == item.brief)
        store.removeBrief(for: item.id)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func launchLineReadsTheBriefFromAFileAndDefaultsToClaude() {
        let line = ScheduledLaunch.commandLine(launch: nil, briefFile: "/tmp/it's.brief")
        #expect(line == #"/bin/zsh -lc 'b="$(cat '\''/tmp/it'\''\'\'''\''s.brief'\'')"; rm -f '\''/tmp/it'\''\'\'''\''s.brief'\''; exec claude "$b"'"#)
        #expect(ScheduledLaunch.commandLine(launch: "  ", briefFile: "/b").hasSuffix(#"exec claude "$b"'"#))
        #expect(ScheduledLaunch.commandLine(launch: "codex --full-auto", briefFile: "/b").contains(#"exec codex --full-auto "$b""#))
        // the profile's seed puts the brief where that CLI reads it; an unknown agent stays positional
        #expect(ScheduledLaunch.commandLine(launch: "gemini", briefFile: "/b").hasSuffix(#"exec gemini -i "$b"'"#))
        #expect(ScheduledLaunch.commandLine(launch: "opencode -m x", briefFile: "/b").hasSuffix(#"exec opencode -m x --prompt "$b"'"#))
        #expect(ScheduledLaunch.commandLine(launch: "my-agent", briefFile: "/b").hasSuffix(#"exec my-agent "$b"'"#))
    }

    @Test func nodeProjectsCountdownStateAndLocalIso() {
        let item = ScheduledSession(fireAt: Self.now.addingTimeInterval(90), brief: "b", name: "n",
                                    workspaceID: UUID(), workspaceName: "w", cwd: "/c", launch: "claude", foreground: true)
        let node = ControlScheduledNode.project(item, now: Self.now, timeZone: Self.zone)
        #expect(node.at == "2026-09-03T00:21:30+05:00")
        #expect(node.inSeconds == 90)
        #expect(node.state == "pending")
        #expect(node.workspace == "w")
        #expect(node.launch == "claude")
        var missed = item
        missed.missedAt = Self.now
        #expect(ControlScheduledNode.project(missed, now: Self.now.addingTimeInterval(200), timeZone: Self.zone).state == "missed")
        #expect(ControlScheduledNode.project(missed, now: Self.now.addingTimeInterval(200), timeZone: Self.zone).inSeconds == -110)
    }
}
