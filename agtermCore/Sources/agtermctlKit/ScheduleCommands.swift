import ArgumentParser
import Foundation
import agtermCore

/// `agtermctl schedule add|list|cancel|run` — sessions the app opens later, seeded with a brief.
struct Schedule: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Schedule a session for later: the app creates it at the time and hands the agent a brief.",
        subcommands: [Add.self, List.self, Cancel.self, Run.self]
    )

    struct Add: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a scheduled session (\(ScheduleTime.acceptedForms))."
        )
        @Option(name: .long, help: "When to open it: +30m, +2h, +1d, HH:MM, 'tomorrow 10:00', 'YYYY-MM-DD HH:MM', or ISO 8601.")
        var at: String
        @Option(name: .long, help: "The task handed to the agent as its first message.")
        var brief: String?
        @Option(name: .long, help: "Read the brief from a file instead of --brief.")
        var briefFile: String?
        @Option(name: .long, help: "Session name.")
        var name: String?
        @Option(name: .long, help: "Workspace id, prefix, or 'active' (defaults to the caller's AGTERM_WORKSPACE_ID, else active).")
        var workspace: String?
        @Option(name: .long, help: "Workspace by exact name, created at fire time when missing.")
        var workspaceName: String?
        @Option(name: .long, help: "Working directory (defaults to the workspace's pinned directory).")
        var cwd: String?
        @Option(name: .long, help: "Connected agent to run, by name or id (defaults to the workspace's agent, else claude).")
        var agent: String?
        @Option(name: .long, help: "Explicit launch line instead of a connected agent.")
        var command: String?
        @Flag(name: .long, help: "Open it in the background instead of selecting it.")
        var background = false
        @OptionGroup var options: ClientOptions

        var echoesResultID: Bool { true }

        func validate() throws {
            guard (brief == nil) != (briefFile == nil) else {
                throw ValidationError("pass exactly one of --brief or --brief-file")
            }
        }

        func makeRequest() throws -> ControlRequest {
            let text: String
            if let briefFile {
                let path = NSString(string: briefFile).expandingTildeInPath
                guard let data = FileManager.default.contents(atPath: path) else {
                    throw ValidationError("cannot read brief file: \(briefFile)")
                }
                text = String(decoding: data, as: UTF8.self)
            } else {
                text = brief ?? ""
            }
            // a scheduled peer should land beside the agent that asked for it, not in the window the user
            // happens to be looking at when the job fires. Same rule `agx spawn` settled on.
            let env = ProcessInfo.processInfo.environment
            let workspace = workspace ?? (workspaceName == nil ? env["AGTERM_WORKSPACE_ID"] : nil)
            return ControlRequest(cmd: .scheduleAdd, args: options.withWindow(ControlArgs(
                name: name, cwd: cwd.map { NSString(string: $0).expandingTildeInPath },
                workspace: workspace, workspaceName: workspaceName, noSelect: background ? true : nil,
                command: command, agent: agent, at: at, brief: text)))
        }
    }

    struct List: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "List scheduled sessions.")
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .scheduleList)
        }
    }

    struct Cancel: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Cancel a scheduled session.")
        @Argument(help: "Schedule id or unique prefix.") var id: String
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .scheduleCancel, target: id)
        }
    }

    struct Run: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Fire a scheduled session now; prints the new session id.")
        @Argument(help: "Schedule id or unique prefix.") var id: String
        @OptionGroup var options: BasicOptions

        var echoesResultID: Bool { true }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .scheduleRun, target: id)
        }
    }
}
