import ArgumentParser
import Foundation
import agtermCore

/// `agtermctl artifact add|list|remove|pin|hide|open|show` — the index of files agents showed the user,
/// and the window that lists them. `add` is what the Claude Code hook and the transcript backfill call.
struct ArtifactCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "artifact",
        abstract: "The artifact index: files and links agents showed you, and the window that lists them.",
        discussion: """
        artifact add ~/out/report.pdf --title "Q3 report"   record a showing (the hook does this for `open`)
        artifact list --workspace mars --kind pdf           what was shown, newest first
        artifact open 3f2a                                   open one in its app (id prefix or path)
        artifact show                                        the Artifacts window (⌘⇧A)
        """,
        subcommands: [Add.self, List.self, Remove.self, Pin.self, Hide.self, Open.self, Show.self]
    )

    struct Add: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Record that a file or URL was shown to the user."
        )
        @Argument(help: "Absolute or ~-relative path, an http(s) URL, or a path relative to --cwd.") var path: String
        @Option(name: .long, help: "Caption shown instead of the file name (max \(ArtifactPolicy.maxTitleLength) characters).")
        var title: String?
        @Option(name: .long, help: "How it was shown: open, reader, sendfile, manual (default), backfill.")
        var source: String?
        @Option(name: .long, help: "Session that showed it (defaults to the caller's AGTERM_SESSION_ID; 'none' records no session).")
        var session: String?
        @Option(name: .long, help: "Directory a relative path resolves against, kept as the artifact's origin.")
        var cwd: String?
        @Option(name: .long, help: "The agent transcript id (Claude Code session uuid) that produced it.")
        var agentSession: String?
        @Option(name: .long, help: "When it was shown, ISO 8601 (defaults to now; backfill passes the transcript time).")
        var seen: String?
        @OptionGroup var options: ClientOptions

        var echoesResultID: Bool { true }

        func makeRequest() throws -> ControlRequest {
            let env = ProcessInfo.processInfo.environment
            var target = session ?? env["AGTERM_SESSION_ID"]
            if target == "none" { target = nil }
            let cwd = cwd ?? FileManager.default.currentDirectoryPath
            return ControlRequest(cmd: .artifactAdd, target: target, args: options.withWindow(ControlArgs(
                cwd: cwd, title: title, path: path, at: seen, transcript: agentSession, source: source)))
        }
    }

    struct List: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "List artifacts, pinned first, then newest first.")
        @Option(name: .long, help: "Only rows whose name, path, session or workspace match every word.")
        var query: String?
        @Option(name: .long, help: "Only rows shown from this workspace (by name).")
        var workspace: String?
        @Option(name: .long, help: "Only this category: pdf, image, document, sheet, slides, media, code, url, other.")
        var kind: String?
        @Option(name: .long, help: "Only rows shown from this session id.")
        var session: String?
        @Flag(name: .long, help: "Include hidden rows.")
        var hidden = false
        @Option(name: .long, help: "At most this many rows.")
        var limit: Int?
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactList, target: session, args: ControlArgs(
                workspace: workspace, query: query, kinds: kind.map { [$0] }, limit: limit, all: hidden ? true : nil))
        }
    }

    struct Remove: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Drop a row from the index. The file is not touched.")
        @Argument(help: "Artifact id, unique prefix, or the exact stored path.") var target: String
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactRemove, target: target)
        }
    }

    struct Pin: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Pin a row to the top of the list (--off unpins).")
        @Argument(help: "Artifact id, unique prefix, or the exact stored path.") var target: String
        @Flag(name: .long, help: "Unpin instead.") var off = false
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactPin, target: target, args: ControlArgs(off: off ? true : nil))
        }
    }

    struct Hide: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Hide a row from the list without deleting it (--off unhides). A later showing unhides it too."
        )
        @Argument(help: "Artifact id, unique prefix, or the exact stored path.") var target: String
        @Flag(name: .long, help: "Unhide instead.") var off = false
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactHide, target: target, args: ControlArgs(off: off ? true : nil))
        }
    }

    struct Open: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Open an artifact in its default app, like a double-click.")
        @Argument(help: "Artifact id, unique prefix, or the exact stored path.") var target: String
        @Flag(name: .long, help: "Reveal it in Finder instead of opening it.") var reveal = false
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactOpen, target: target, args: ControlArgs(mode: reveal ? "reveal" : nil))
        }
    }

    struct Show: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Show the Artifacts window.")
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .artifactShow, args: options.withWindow())
        }
    }
}
