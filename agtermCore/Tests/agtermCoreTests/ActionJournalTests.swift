import Foundation
import Testing
@testable import agtermCore

struct ActionJournalTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    private func lines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    @Test func recordsOneJSONObjectPerLineWithTimestampAndKind() throws {
        let dir = tempDir()
        let fixed = Date(timeIntervalSince1970: 1_783_969_641.38)
        let journal = ActionJournal(directory: dir, now: { fixed })
        journal.log("key", ["chord": "cmd+j", "produced": "о"])
        journal.log("state", ["scratch": "on"])
        journal.flush()
        let got = lines(try #require(journal.fileURL))
        #expect(got.count == 2)
        let first = try #require(try JSONSerialization.jsonObject(with: Data(got[0].utf8)) as? [String: String])
        #expect(first["kind"] == "key")
        #expect(first["chord"] == "cmd+j")
        #expect(first["produced"] == "о")
        #expect(first["ts"] == "2026-07-13T19:07:21.380Z")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func unconfiguredJournalWritesNothing() {
        let journal = ActionJournal()
        journal.log("key", ["chord": "cmd+j"])
        journal.flush()
        #expect(journal.fileURL == nil)
    }

    @Test func rotatesOnceWhenPastMaxBytes() throws {
        let dir = tempDir()
        let journal = ActionJournal(directory: dir, maxBytes: 120)
        for i in 0..<6 { journal.log("key", ["n": "\(i)"]) }
        journal.flush()
        let live = try #require(journal.fileURL)
        let rotated = dir.appendingPathComponent(ActionJournal.rotatedFileName)
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        #expect(lines(live).count + lines(rotated).count == 6)
        #expect(lines(live).count < 6)
        try? FileManager.default.removeItem(at: dir)
    }
}
