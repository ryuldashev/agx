import Foundation
import Testing
@testable import agtermCore

struct ControlResolveTests {
    private let a = UUID(uuidString: "9F3CAAAA-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "9FABBBBB-0000-0000-0000-000000000002")!
    private let c = UUID(uuidString: "1234CCCC-0000-0000-0000-000000000003")!

    @Test func activeResolvesToActiveID() {
        let result = ControlResolve.resolve("active", candidates: [a, b, c], active: b)
        #expect(result == .resolved(b))
    }

    @Test func activeWithNilActiveIsNotFound() {
        let result = ControlResolve.resolve("active", candidates: [a, b, c], active: nil)
        #expect(result == .notFound)
    }

    @Test func exactUUIDResolves() {
        let result = ControlResolve.resolve(a.uuidString, candidates: [a, b, c], active: nil)
        #expect(result == .resolved(a))
    }

    @Test func exactUUIDIsCaseInsensitive() {
        let result = ControlResolve.resolve(a.uuidString.lowercased(), candidates: [a, b, c], active: nil)
        #expect(result == .resolved(a))
    }

    @Test func uniquePrefixResolves() {
        // "1234" is unique to c
        let result = ControlResolve.resolve("1234", candidates: [a, b, c], active: nil)
        #expect(result == .resolved(c))
    }

    @Test func ambiguousPrefixListsHits() {
        // "9f" matches both a and b
        let result = ControlResolve.resolve("9f", candidates: [a, b, c], active: nil)
        #expect(result == .ambiguous([a, b]))
    }

    @Test func noMatchIsNotFound() {
        let result = ControlResolve.resolve("deadbeef", candidates: [a, b, c], active: nil)
        #expect(result == .notFound)
    }

    @Test func emptyCandidatesIsNotFound() {
        let result = ControlResolve.resolve("9f", candidates: [], active: nil)
        #expect(result == .notFound)
    }

    @Test func emptyTargetIsNotFound() {
        // an empty prefix would otherwise match every candidate — guard it to .notFound.
        #expect(ControlResolve.resolve("", candidates: [a, b, c], active: a) == .notFound)
        #expect(ControlResolve.resolve("", candidates: [a], active: nil) == .notFound)
    }

    @Test func notFoundMessageUsesControlWireString() {
        let message = ControlResolve.notFoundMessage(noun: "session", target: "deadbeef")
        #expect(message == "no such session: deadbeef")
    }

    @Test func ambiguousMessageUsesControlWireStringWithPrefix8List() {
        let message = ControlResolve.ambiguousMessage(noun: "window", target: "9f", hits: [a, b])
        #expect(message == "ambiguous window prefix '9f' → 9F3CAAAA, 9FABBBBB")
    }

    @Test func errorMessageUsesAmbiguousWireString() {
        let message = ControlResolve.errorMessage(noun: "workspace", target: "9f", resolution: .ambiguous([a, b]))
        #expect(message == "ambiguous workspace prefix '9f' → 9F3CAAAA, 9FABBBBB")
    }

    @Test func errorMessageMapsNonAmbiguousResultsToNotFoundWireString() {
        #expect(ControlResolve.errorMessage(noun: "session", target: "active", resolution: .notFound) == "no such session: active")
        #expect(ControlResolve.errorMessage(noun: "session", target: "active", resolution: .resolved(a)) == "no such session: active")
    }

    // window-id targets reuse the same pure matcher; WindowLibrary supplies the ordered window set and
    // the active-window fallback around it.
    private let w1 = UUID(uuidString: "0A11AAAA-0000-0000-0000-000000000011")!
    private let w2 = UUID(uuidString: "0A22BBBB-0000-0000-0000-000000000012")!
    private let w3 = UUID(uuidString: "7B33CCCC-0000-0000-0000-000000000013")!

    @Test func windowActiveResolvesToFrontmost() {
        let result = ControlResolve.resolve("active", candidates: [w1, w2, w3], active: w2)
        #expect(result == .resolved(w2))
    }

    @Test func windowExactUUIDResolves() {
        let result = ControlResolve.resolve(w1.uuidString, candidates: [w1, w2, w3], active: nil)
        #expect(result == .resolved(w1))
    }

    @Test func windowUniquePrefixResolves() {
        // "7b33" is unique to w3
        let result = ControlResolve.resolve("7b33", candidates: [w1, w2, w3], active: nil)
        #expect(result == .resolved(w3))
    }

    @Test func windowAmbiguousPrefixListsHits() {
        // "0a" matches both w1 and w2
        let result = ControlResolve.resolve("0a", candidates: [w1, w2, w3], active: nil)
        #expect(result == .ambiguous([w1, w2]))
    }

    @Test func windowNoMatchIsNotFound() {
        let result = ControlResolve.resolve("deadbeef", candidates: [w1, w2, w3], active: nil)
        #expect(result == .notFound)
    }

    @Test func namesMatchExactlyAndCaseInsensitively() {
        let candidates = [(id: w1, name: "mmee"), (id: w2, name: "Agterm"), (id: w3, name: "notes")]
        #expect(ControlResolve.idsNamed("mmee", candidates: candidates) == [w1])
        #expect(ControlResolve.idsNamed("AGTERM", candidates: candidates) == [w2])
        #expect(ControlResolve.idsNamed(" notes ", candidates: candidates) == [w3])
    }

    @Test func namesDoNotPrefixMatch() {
        #expect(ControlResolve.idsNamed("mm", candidates: [(id: w1, name: "mmee")]).isEmpty)
        #expect(ControlResolve.idsNamed("", candidates: [(id: w1, name: "mmee")]).isEmpty)
    }

    @Test func duplicateNamesReturnEveryMatchInCandidateOrder() {
        let candidates = [(id: w1, name: "work"), (id: w2, name: "other"), (id: w3, name: "work")]
        #expect(ControlResolve.idsNamed("work", candidates: candidates) == [w1, w3])
    }

    /// The prefix wording would misname a genuine name collision, so the two errors are separate strings.
    @Test func ambiguousNameMessageNamesTheCollisionAndTheWayOut() {
        let message = ControlResolve.ambiguousNameMessage(noun: "workspace", target: "work", hits: [w1, w2])
        #expect(message == "ambiguous workspace name 'work' → \(w1.uuidString.prefix(8)), \(w2.uuidString.prefix(8)) (address it by id)")
    }

    @Test func socketPathWithStateDir() {
        let path = ControlResolve.socketPath(stateDir: "/tmp/agterm-state", appSupport: "/Users/x/Library/Application Support/agterm")
        #expect(path == "/tmp/agterm-state/\(Brand.socketFileName)")
    }

    @Test func socketPathWithoutStateDirUsesAppSupport() {
        let path = ControlResolve.socketPath(stateDir: nil, appSupport: "/Users/x/Library/Application Support/agterm")
        #expect(path == "/Users/x/Library/Application Support/agterm/\(Brand.socketFileName)")
    }
}
