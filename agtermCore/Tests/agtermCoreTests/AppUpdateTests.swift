import Foundation
import Testing
@testable import agtermCore

struct AppUpdateTests {
    @Test func policyEnablesOnlyAReleaseBuildWithARealVersion() {
        #expect(AppUpdatePolicy.isEnabled(version: "0.25.0", isDebugBuild: false, environment: [:]))
        #expect(!AppUpdatePolicy.isEnabled(version: "0.25.0", isDebugBuild: true, environment: [:]))
        #expect(!AppUpdatePolicy.isEnabled(version: "0.0.0", isDebugBuild: false, environment: [:]))
        #expect(!AppUpdatePolicy.isEnabled(version: "unknown", isDebugBuild: false, environment: [:]))
        #expect(!AppUpdatePolicy.isEnabled(version: nil, isDebugBuild: false, environment: [:]))
    }

    @Test(arguments: [
        ["AGX_NO_UPDATE": "1"],
        ["AGTERM_STATE_DIR": "/tmp/x"],
        ["AGTERM_HOSTED_TESTS": "1"],
        ["AGTERM_UITEST_FORCE_SIDEBAR_VISIBLE": "1"],
    ])
    func policyDisablesIsolatedAndOptedOutInstances(environment: [String: String]) {
        #expect(!AppUpdatePolicy.isEnabled(version: "0.25.0", isDebugBuild: false, environment: environment))
    }

    @Test func stagingFeedLiftsEveryGateButTheOptOut() {
        let staging = ["AGX_UPDATE_FEED": "file:///tmp/appcast.xml", "AGTERM_STATE_DIR": "/tmp/x"]
        #expect(AppUpdatePolicy.isEnabled(version: "0.0.0", isDebugBuild: true, environment: staging))
        #expect(AppUpdatePolicy.stagingFeed(environment: staging) == "file:///tmp/appcast.xml")
        #expect(!AppUpdatePolicy.isEnabled(version: "0.25.0", isDebugBuild: false,
                                           environment: staging.merging(["AGX_NO_UPDATE": "1"]) { $1 }))
        #expect(AppUpdatePolicy.stagingFeed(environment: ["AGX_UPDATE_FEED": ""]) == nil)
    }

    @Test func policyIgnoresAnOptOutThatIsNotOne() {
        #expect(AppUpdatePolicy.isEnabled(version: "0.25.0", isDebugBuild: false, environment: ["AGX_NO_UPDATE": "0"]))
    }

    @Test func nodeRoundTripsAndOmitsNilFields() throws {
        let node = ControlUpdateNode(version: "0.24.0", state: "idle", automatic: true)
        let data = try JSONEncoder().encode(node)
        #expect(try JSONDecoder().decode(ControlUpdateNode.self, from: data) == node)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("available") && !json.contains("lastChecked") && !json.contains("error"))
    }

    @Test func treeAndResultOmitTheUpdateNodeWhenDisabled() throws {
        let tree = ControlTree(workspaces: [])
        #expect(!String(decoding: try JSONEncoder().encode(tree), as: UTF8.self).contains("update"))
        let result = ControlResult(id: "x")
        #expect(!String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("update"))
        let carried = ControlResult(update: ControlUpdateNode(version: "0.24.0", state: "available",
                                                              available: "0.25.0", automatic: false))
        let decoded = try JSONDecoder().decode(ControlResult.self, from: JSONEncoder().encode(carried))
        #expect(decoded == carried)
    }

    @Test(arguments: [
        (ControlUpdateNode(version: "0.24.0", state: "idle", automatic: true), "agx 0.24.0 — not checked yet"),
        (ControlUpdateNode(version: "0.24.0", state: "idle", lastChecked: "2026-09-13T15:00:00+05:00", automatic: true),
         "agx 0.24.0 — up to date (checked 2026-09-13T15:00:00+05:00)"),
        (ControlUpdateNode(version: "0.24.0", state: "available", available: "0.25.0", automatic: true),
         "agx 0.24.0 — available: 0.25.0 available (agtermctl update install)"),
        (ControlUpdateNode(version: "0.24.0", state: "downloading", available: "0.25.0", automatic: false),
         "agx 0.24.0 — downloading: 0.25.0 available [automatic checks off]"),
        (ControlUpdateNode(version: "0.24.0", state: "checking", automatic: true), "agx 0.24.0 — checking"),
        (ControlUpdateNode(version: "0.24.0", state: "error", automatic: true, error: "offline"),
         "agx 0.24.0 — error: offline"),
    ])
    func humanDescriptionReadsTheState(node: ControlUpdateNode, expected: String) {
        #expect(node.humanDescription == expected)
    }
}
