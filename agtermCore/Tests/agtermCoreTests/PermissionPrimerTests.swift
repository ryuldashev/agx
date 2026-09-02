import Testing
@testable import agtermCore

struct PermissionPrimerTests {
    @Test func dueUntilShown() {
        #expect(PermissionPrimer.isDue(primerShown: nil))
        #expect(PermissionPrimer.isDue(primerShown: false))
        #expect(!PermissionPrimer.isDue(primerShown: true))
    }

    @Test func areaIDsAreUnique() {
        let ids = PermissionPrimer.areas.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func probeableAreasCarryAHomeRelativePath() {
        #expect(!PermissionPrimer.probeableAreas.isEmpty)
        for area in PermissionPrimer.probeableAreas {
            let path = try! #require(area.probePath)
            // a probe is resolved against the home directory; an absolute one would escape it silently
            #expect(!path.hasPrefix("/"))
            #expect(area.settingsAnchor == nil)
        }
    }

    @Test func settingsRowsCarryAPreferencesURL() {
        let settingsRows = PermissionPrimer.areas.filter { $0.probePath == nil }
        #expect(!settingsRows.isEmpty)
        for area in settingsRows {
            #expect(area.settingsAnchor?.hasPrefix("x-apple.systempreferences:") == true)
        }
    }

    @Test func everyAreaExplainsWhoAsks() {
        for area in PermissionPrimer.areas {
            #expect(!area.title.isEmpty)
            #expect(area.reason.count > 20)
        }
    }

    @Test func summaryPointsADenialAtSystemSettings() {
        let area = PermissionPrimer.areas[0]
        #expect(PermissionPrimer.summaryLine(area: area, status: .granted).hasSuffix("granted"))
        #expect(PermissionPrimer.summaryLine(area: area, status: .denied).contains("System Settings"))
        #expect(PermissionPrimer.summaryLine(area: area, status: .absent).contains("nothing on this Mac"))
    }

    @Test func runningLineNamesWorkspaceSessionAndCommand() {
        let line = PermissionPrimer.runningLine(workspace: "mars", session: "Оценка компании",
                                                argv: ["du", "-sh", "/Users/rus/Music"])
        #expect(line == "mars ▸ Оценка компании — du -sh /Users/rus/Music")
    }

    @Test func runningLineClipsALongCommand() {
        let argv = ["find", String(repeating: "x", count: 200)]
        let line = PermissionPrimer.runningLine(workspace: "w", session: "s", argv: argv)
        #expect(line.hasSuffix("…"))
        #expect(line.count < 140)
    }
}
