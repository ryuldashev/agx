import Foundation
import Testing
@testable import agtermCore

@MainActor
struct AppStoreReaderTests {
    @Test func openReaderReportsItsSpecInTheTree() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        #expect(store.openReader(session.id, spec: ReaderSpec(path: "/repo/plan.md", position: .centerLeft,
                                                              sizePercent: 50)))

        let node = try #require(store.controlTree().workspaces[0].sessions.first)
        #expect(node.reader == ControlReaderNode(path: "/repo/plan.md", position: "center-left", sizePercent: 50))
        #expect(session.readerActive)
    }

    @Test func theReadBackIsOmittedWithNoReaderUp() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        _ = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        let node = try #require(store.controlTree().workspaces[0].sessions.first)
        let json = String(decoding: try JSONEncoder().encode(node), as: UTF8.self)

        #expect(node.reader == nil)
        #expect(!json.contains("\"reader\""), "no reader must be omitted from the JSON; got \(json)")
    }

    @Test func theWidthIsBoundedOnBothSides() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md", sizePercent: 100))
        #expect(session.readerSpec?.sizePercent == ReaderLayout.maxSizePercent)

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md", sizePercent: 1))
        #expect(session.readerSpec?.sizePercent == ReaderLayout.minSizePercent)
    }

    @Test func aSecondOpenReplacesTheFirstAndBumpsTheGeneration() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        let first = session.readerSlotGeneration
        store.openReader(session.id, spec: ReaderSpec(path: "/b.md"))

        #expect(session.readerSpec?.path == "/b.md")
        #expect(session.readerSlotGeneration == first + 1)
    }

    @Test func closeReaderClearsTheStateAndRefusesAnEmptySlot() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        #expect(!store.closeReader(session.id))
        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        #expect(store.closeReader(session.id))
        #expect(!session.readerActive)
        #expect(store.controlTree().workspaces[0].sessions.first?.reader == nil)
    }

    @Test func aReaderLeavesTheOverlaySlotAlone() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))

        #expect(!session.overlayActive)
        #expect(!session.programOverlayActive)
        #expect(store.openOverlay(session.id, command: "top"))
        #expect(session.readerActive, "a program overlay must not take the reader down")
    }

    @Test func openReaderRefusesAnUnknownSession() {
        let store = makeStore()
        #expect(!store.openReader(UUID(), spec: ReaderSpec(path: "/a.md")))
    }

    @Test func theReaderIsNotPersisted() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))
        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))

        let data = try JSONEncoder().encode(store.snapshot())

        #expect(!String(decoding: data, as: UTF8.self).contains("/a.md"))
    }
}
