import ArgumentParser
import Foundation
import agtermCore

/// `agtermctl update check|status|install` — the in-app updater (ADR 0003). App-global, no target.
struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check for, read, or install an app update.",
        discussion: """
        update check     ask the feed now, in the background; the answer lands in `update status`
        update status    the running version and what the last check found (also `tree` → update)
        update install   open the update dialog: download, verify, and relaunch on confirmation

        Absent from `tree` and refused here when the updater is off: a 0.0.0 local build, a Debug build,
        an isolated instance (AGTERM_STATE_DIR), or AGX_NO_UPDATE=1.
        """,
        subcommands: [Check.self, Status.self, Install.self]
    )

    struct Check: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Check the feed in the background.")
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest { ControlRequest(cmd: .updateCheck) }
    }

    struct Status: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Running version and the last check's outcome.")
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest { ControlRequest(cmd: .updateStatus) }
    }

    struct Install: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show the update dialog for the available version (the user confirms the relaunch)."
        )
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest { ControlRequest(cmd: .updateInstall) }
    }
}
