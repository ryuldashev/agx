import Foundation
import ArgumentParser
import agtermCore

// MARK: - workspace

struct Workspace: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Workspace commands.",
        subcommands: [New.self, Rename.self, Delete.self, Select.self, Go.self, Move.self, Focus.self, Filter.self,
                      Collapse.self, Expand.self, Defaults.self]
    )

    struct New: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Create a workspace.")
        @Argument(help: "Workspace name (defaults to the auto-generated name).") var name: String?
        @Flag(name: .long, help: "Create the workspace collapsed in the sidebar.") var collapsed = false
        @OptionGroup var options: ClientOptions
        var echoesResultID: Bool { true }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceNew, args: options.withWindow(ControlArgs(name: name, collapsed: collapsed ? true : nil)))
        }
    }

    struct Rename: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a workspace.")
        @Argument(help: "New workspace name.") var name: String
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceRename, target: target.target, args: options.withWindow(ControlArgs(name: name)))
        }
    }

    struct Delete: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a workspace.")
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceDelete, target: target.target, args: options.withWindow())
        }
    }

    struct Select: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Select a workspace.")
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceSelect, target: target.target, args: options.withWindow())
        }
    }

    /// `agtermctl workspace go --to next|prev` — steps the CURRENT workspace and selects its first session.
    /// Deliberately NO `--target`: it is relative to what is current, the shape `session go` takes, not the
    /// `workspace.*` target commands. `move` is the neighbouring verb that REORDERS instead.
    struct Go: RequestCommand {
        static let configuration = CommandConfiguration(commandName: "go",
            abstract: "Navigate workspaces: next|prev.")
        @Option(name: .long, help: "Direction: next or prev.") var to: String
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceGo, args: options.withWindow(ControlArgs(to: to)))
        }
    }

    struct Move: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Reorder a workspace among its siblings.")
        @Option(name: .long, help: "Direction: up, down, top, or bottom.") var to: String
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceMove, target: target.target, args: options.withWindow(ControlArgs(to: to)))
        }
    }

    /// `agtermctl workspace focus [on|off|toggle|add] [--target W]` — marks or unmarks ONE workspace in the
    /// sidebar's focus set; `add` only marks, applying the set is `workspace filter on`. The accepted list, the
    /// per-mode help prose, and the rejection message all derive from `ControlWorkspaceFocusMode.allCases` (via
    /// `validNamesList`/`helpPhrase`/`validNamesPhrase`), so a new case reaches each and cannot drift from it.
    struct Focus: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Mark a workspace in the sidebar focus set (\(ControlWorkspaceFocusMode.validNamesList))."
        )
        @Argument(help: "Mode: \(ControlWorkspaceFocusMode.helpPhrase).")
        var mode: String = ControlWorkspaceFocusMode.toggle.rawValue
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws {
            guard ControlWorkspaceFocusMode(rawValue: mode) != nil else {
                throw ValidationError("mode must be one of: \(ControlWorkspaceFocusMode.validNamesPhrase)")
            }
        }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceFocus, target: target.target, args: options.withWindow(ControlArgs(mode: mode)))
        }
    }

    /// `agtermctl workspace filter [on|off|toggle] [--window W]` — turns the sidebar's workspace focus filter
    /// on or off for a WHOLE window, leaving the marked set intact. Deliberately NO `--target`: it flips the
    /// window's filter rather than one workspace, so its shape is `sidebar expand`/`collapse` (`ClientOptions`
    /// only), not the `workspace.*` target commands. The three mode names are spelled out rather than derived:
    /// `ControlToggleMode` carries no `validNames` (its tokens are per-command — `sidebar` spells the same
    /// three `show|hide|toggle`), so this matches `session flag`/`sidebar mode`, not the enum-derived `Focus`.
    struct Filter: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Turn the sidebar workspace focus filter on or off (on|off|toggle)."
        )
        @Argument(help: "Mode: on, off, or toggle (default).") var mode: String = "toggle"
        @OptionGroup var options: ClientOptions

        func validate() throws {
            guard ["on", "off", "toggle"].contains(mode) else {
                throw ValidationError("mode must be on, off, or toggle")
            }
        }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceFilter, args: options.withWindow(ControlArgs(mode: mode)))
        }
    }

    struct Collapse: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Collapse a workspace in the sidebar tree.")
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceCollapse, target: target.target, args: options.withWindow())
        }
    }

    /// `agtermctl workspace defaults [--dir PATH] [--agent NAME] [--background IMG] [--target W]` — shows the workspace's
    /// new-session seed, or sets it. Each option is independent and an EMPTY value clears just that one, so
    /// `--dir ""` unpins the directory without touching the agent. With neither option it only reads.
    struct Defaults: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show or set a workspace's default directory and agent for new sessions."
        )
        @Option(name: .long, help: "Directory new sessions open in; pass an empty string to clear it.")
        var dir: String?
        @Option(name: .long, help: "Connected agent to run, by name or id; pass an empty string to clear it.")
        var agent: String?
        @Option(name: .long, help: "Background image (PNG/JPEG) for new sessions here; empty string clears it.")
        var background: String?
        @Option(name: .long, help: "Background image opacity 0...1 (applies to the pinned image).")
        var backgroundOpacity: Double?
        @Option(name: .long, help: "Background image fit: contain|cover|stretch|none.")
        var backgroundFit: String?
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            // ~ is expanded HERE: the path is handed to ghostty verbatim, and a literal "~/x" file does not
            // exist, so an unexpanded one would fail validation with a confusing "no such image file".
            let image = background.map { $0.isEmpty ? $0 : NSString(string: $0).expandingTildeInPath }
            return ControlRequest(cmd: .workspaceDefaults, target: target.target,
                                  args: options.withWindow(ControlArgs(cwd: dir, path: image,
                                                                       opacity: backgroundOpacity,
                                                                       fit: backgroundFit, agent: agent)))
        }
    }

    struct Expand: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Expand a workspace in the sidebar tree.")
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .workspaceExpand, target: target.target, args: options.withWindow())
        }
    }
}
