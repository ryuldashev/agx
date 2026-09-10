import Foundation
import Testing
@testable import agtermCore

@MainActor
struct AppStoreReaderTests {
    @Test func openReaderReportsItsPathInTheTree() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        #expect(store.openReader(session.id, spec: ReaderSpec(path: "/repo/plan.md")))

        let node = try #require(store.controlTree().workspaces[0].sessions.first)
        #expect(node.reader == ControlReaderNode(path: "/repo/plan.md"))
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

    @Test func openingOnAnUnsplitSessionShowsTheSplitAtTheDefaultWidthAndKeepsTheShellFocused() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))

        #expect(session.isSplit)
        #expect(session.splitAxis == .leftRight)
        #expect(!session.splitFocused, "the reader is not typed into; the shell keeps focus")
        let ratio = try #require(session.splitRatio)
        #expect(abs(ratio - ReaderLayout.splitRatio(forSizePercent: ReaderLayout.defaultSizePercent)) < 0.001)
    }

    @Test func theWidthIsBoundedOnBothSides() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md", sizePercent: 100))
        #expect(session.splitRatio == 1 - Double(ReaderLayout.maxSizePercent) / 100)

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md", sizePercent: 1))
        #expect(session.splitRatio == 1 - Double(ReaderLayout.minSizePercent) / 100)
    }

    @Test func openingOnASplitSessionKeepsItsRatio() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))
        store.setSplitVisibility(session.id, shown: true)
        store.applySplitRatio(0.7, forSession: session.id)

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))

        #expect(session.splitRatio == 0.7, "a split the user sized stays as sized")
        #expect(!session.readerShowedSplit)
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
        #expect(session.readerShowedSplit, "the replacement still owes the split it inherited")
    }

    @Test func closeReaderTakesDownTheSplitItShowedAndRefusesAnEmptySlot() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        #expect(!store.closeReader(session.id))
        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        #expect(store.closeReader(session.id))

        #expect(!session.readerActive)
        #expect(!session.isSplit)
        #expect(!session.hasSplit, "no shell ever ran in the pane, so nothing is left to hide")
        #expect(store.controlTree().workspaces[0].sessions.first?.reader == nil)
    }

    @Test func closeReaderLeavesAPreexistingSplitUp() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))
        store.setSplitVisibility(session.id, shown: true)

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        store.closeReader(session.id)

        #expect(session.isSplit, "the shell pane the reader borrowed comes back")
        #expect(!session.readerActive)
    }

    @Test func hidingOrClosingTheSplitTakesTheReaderWithIt() throws {
        let store = makeStore()
        let ws = store.addWorkspace(name: "work")
        let session = try #require(store.addSession(toWorkspace: ws.id, cwd: "/repo"))

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        store.setSplitVisibility(session.id, shown: false)
        #expect(!session.readerActive)
        #expect(!session.readerShowedSplit)

        store.openReader(session.id, spec: ReaderSpec(path: "/a.md"))
        store.closeSplit(session.id)
        #expect(!session.readerActive)
        #expect(!session.hasSplit)
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
