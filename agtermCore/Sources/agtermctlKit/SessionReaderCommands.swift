import ArgumentParser
import Foundation
import agtermCore

// MARK: - session reader

/// In its own file, and as an extension, because `SessionCommands.swift` sits at the file and type-length
/// limits; the command is still reached through `Session.configuration.subcommands`.
extension Session {
    /// The markdown reader panel. `Open` is the default subcommand, so showing a file is
    /// `agtermctl session reader notes.md`; a file literally named `close` needs the explicit `reader open`
    /// verb. The path is resolved HERE against the caller's cwd — the socket carries an absolute path, and
    /// the app never guesses a base for a relative one.
    struct Reader: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show a markdown file in a live-reloading panel over a session, or take it down.",
            subcommands: [Open.self, Close.self],
            defaultSubcommand: Open.self
        )

        /// `~` expanded and a relative path anchored at the caller's cwd, then standardized so `tree`
        /// reports the path the caller would recognize rather than one with `..` segments.
        static func absolutePath(_ path: String) -> String {
            let expanded = NSString(string: path).expandingTildeInPath
            let anchored = expanded.hasPrefix("/")
                ? expanded
                : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
            return NSString(string: anchored).standardizingPath
        }

        struct Open: RequestCommand {
            static let configuration = CommandConfiguration(
                abstract: "Show a markdown file beside the session; it re-renders as the file changes on disk.")
            @Argument(help: "Path to the .md file, relative to the current directory.") var path: String
            @Option(name: .long, help: """
                Placement in the pane: \(HudPosition.acceptedNamesPhrase) \
                (default: \(ReaderLayout.defaultPosition.rawValue)); only the column matters, the panel runs \
                nearly the pane's full height.
                """)
            var position: String?
            @Option(name: .long, help: """
                Panel WIDTH as a percent of the pane (default: \(ReaderLayout.defaultSizePercent)); bounded to \
                \(ReaderLayout.minSizePercent)-\(ReaderLayout.maxSizePercent), so it stays readable and never \
                covers the session.
                """)
            var sizePercent: Int?
            @OptionGroup var target: TargetOptions
            @OptionGroup var options: ClientOptions

            func validate() throws {
                try Hud.validatePosition(position)
                try Hud.validateSizePercent(sizePercent)
            }

            func makeRequest() throws -> ControlRequest {
                ControlRequest(cmd: .sessionReaderOpen, target: target.target,
                               args: options.withWindow(ControlArgs(sizePercent: sizePercent,
                                                                    path: Reader.absolutePath(path),
                                                                    position: position)))
            }
        }

        struct Close: RequestCommand {
            static let configuration = CommandConfiguration(abstract: "Take the reader panel down.")
            @OptionGroup var target: TargetOptions
            @OptionGroup var options: ClientOptions

            func makeRequest() throws -> ControlRequest {
                ControlRequest(cmd: .sessionReaderClose, target: target.target, args: options.withWindow())
            }
        }
    }
}
