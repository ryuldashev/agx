import Foundation
import Testing
@testable import agtermCore

struct OnboardingTests {
    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("onboarding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func agxSpawnIsASessionNewMarkedByTheCLI() {
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "session.new", "via": "agx-spawn"]) == [.spawn])
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "session.new"]).isEmpty)
    }

    @Test func controlCommandsMapToTheirCapability() {
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "session.reader.open"]) == [.reader])
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "session.overlay.open"]) == [.overlay])
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "schedule.add"]) == [.schedule])
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "session.status"]) == [.statusGlyph])
        #expect(Discovery.matches(kind: "control", fields: ["cmd": "tree"]).isEmpty)
    }

    @Test func paletteRunOfTheQuickTerminalCountsForBoth() {
        let found = Discovery.matches(kind: "action", fields: ["source": "palette", "action": "quickTerminal"])
        #expect(Set(found) == [.palette, .quickTerminal])
        #expect(Discovery.matches(kind: "action", fields: ["source": "keymap", "action": "quick_terminal"]) == [.quickTerminal])
        #expect(Discovery.matches(kind: "action", fields: ["source": "keymap", "action": "new_session"]).isEmpty)
    }

    @Test func stateFlipsCountOnlyWhenTurnedOn() {
        #expect(Discovery.matches(kind: "state", fields: ["split": "on"]) == [.split])
        #expect(Discovery.matches(kind: "state", fields: ["split": "off"]).isEmpty)
        #expect(Discovery.matches(kind: "state", fields: ["dashboard": "on"]) == [.dashboard])
        #expect(Discovery.matches(kind: "state", fields: ["hints": "on"]) == [.optionHints])
        #expect(Discovery.matches(kind: "state", fields: ["failover": "handoff"]) == [.failover])
        #expect(Discovery.matches(kind: "key", fields: ["chord": "cmd+d"]).isEmpty)
    }

    @Test func everyDiscoveryHasCopyAndAGuideChapter() {
        for discovery in Discovery.allCases {
            #expect(!discovery.title.isEmpty)
            #expect(!discovery.hint.isEmpty)
            #expect(discovery.guide.hasSuffix(".md") || discovery.guide.contains(".md#"))
        }
        #expect(Discovery.firstMoves.count == 6)
    }

    @Test func trackerRecordsTheFirstTimeOnlyAndPersists() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiscoveryStore(directory: dir)
        let first = Date(timeIntervalSince1970: 1_000)
        let tracker = DiscoveryTracker(store: store, now: { first })
        #expect(tracker.record(.split))
        #expect(!tracker.record(.split))
        tracker.observe(kind: "control", fields: ["cmd": "session.reader.open"])
        #expect(tracker.count == 2)

        let reloaded = DiscoveryTracker(store: store)
        #expect(reloaded.isDiscovered(.split))
        #expect(reloaded.isDiscovered(.reader))
        #expect(reloaded.discovered[.split].map { Int($0.timeIntervalSince1970) } == 1_000)
        reloaded.reset()
        #expect(DiscoveryStore(directory: dir).load().isEmpty)
    }

    @Test func storeDropsIdsItDoesNotKnow() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DiscoveryStore(directory: dir)
        try Data(#"{"split":"2026-09-12T00:00:00Z","teleport":"2026-09-12T00:00:00Z"}"#.utf8).write(to: store.fileURL)
        #expect(store.load().keys.sorted { $0.rawValue < $1.rawValue } == [.split])
    }

    @Test func trackerFollowsTheJournal() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = ActionJournal(directory: dir)
        let tracker = DiscoveryTracker(store: nil)
        tracker.attach(to: journal)
        journal.log("state", ["scratch": "on"])
        journal.flush()
        #expect(tracker.isDiscovered(.scratch))
    }

    @Test func setupIsCompleteWhenRequiredRowsAreDone() {
        var states: [OnboardingSetup.Step: OnboardingSetup.State] = [:]
        for step in OnboardingSetup.Step.allCases { states[step] = .done(nil) }
        states[.toolPermissions] = .optional("None granted")
        #expect(OnboardingSetup.isComplete(states))
        states[.cli] = .pending(nil)
        #expect(!OnboardingSetup.isComplete(states))
        #expect(!OnboardingSetup.isComplete([:]))
    }

    @Test func aLinkIsOursOnlyInsideTheBundle() {
        let bundle = "/Applications/agx.app"
        #expect(OnboardingSetup.linkPointsIntoBundle("/Applications/agx.app/Contents/MacOS/agtermctl", bundlePath: bundle))
        #expect(OnboardingSetup.linkPointsIntoBundle("/Applications/agx.app/Contents/Resources/agx", bundlePath: bundle + "/"))
        #expect(!OnboardingSetup.linkPointsIntoBundle("/Applications/agx.app.old/Contents/MacOS/agtermctl", bundlePath: bundle))
        #expect(!OnboardingSetup.linkPointsIntoBundle("/opt/homebrew/bin/agtermctl", bundlePath: bundle))
    }
}
