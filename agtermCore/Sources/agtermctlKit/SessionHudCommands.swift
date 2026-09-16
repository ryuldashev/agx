import ArgumentParser
import Foundation
import agtermCore

// MARK: - session hud

/// In its own file, and as an extension, for the reason `SessionReaderCommands.swift` states: the command
/// is still reached through `Session.configuration.subcommands`.
extension Session {
    /// The passive message panel. `Open` is the default subcommand, so posting one is
    /// `agtermctl session hud "gathering options…"`; a message that is literally `update` or `close` needs
    /// the explicit `hud open` verb. Message length and control characters are the dispatcher's to reject —
    /// only what needs no socket is checked here.
    struct Hud: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Post, update, or close a passive message panel over a session.",
            subcommands: [Open.self, Update.self, Close.self],
            defaultSubcommand: Open.self
        )

        /// `--position` help and validation both derive from `HudPosition`, so a new case reaches each.
        /// Accepts the `top`/`bottom` aliases exactly as the dispatcher does, for the reason
        /// `validateSpinnerStyle` states about `none`: refusing one here would fail a value the identical
        /// raw-socket request takes.
        static func validatePosition(_ position: String?) throws {
            if let position, HudPosition.parse(position) == nil {
                throw ValidationError("position must be one of: \(HudPosition.acceptedNamesPhrase)")
            }
        }

        /// Shared by open and update, which both set the panel's text color; `--background-color` has no
        /// update counterpart because only the text color rides the header a live panel re-reads.
        static func validateTextColor(_ textColor: String?) throws {
            if let textColor, !WatermarkConfig.isValidColorHex(textColor) {
                throw ValidationError("text-color must be a #rrggbb hex value")
            }
        }

        /// Accepts `HudSpinner.noneName` beside the styles, exactly as the dispatcher does: `none` is what
        /// the read-back reports for a static panel, and refusing it here would make a value `tree` just
        /// handed the caller fail locally while the identical raw-socket request succeeds.
        static func validateSpinnerStyle(_ style: String?) throws {
            if let style, style != HudSpinner.noneName, HudSpinner(rawValue: style) == nil {
                throw ValidationError("spinner style must be one of: \(HudSpinner.acceptedNamesPhrase)")
            }
        }

        /// The one spinner value the socket carries, from the two ways to ask for one: `--spinner-style`
        /// names it and turns it on by itself, so the bare `--spinner` flag is only needed for the default.
        /// Nil when neither is given, which is the static panel.
        ///
        /// An explicit `--spinner-style none` also resolves to nil, and beats a bare `--spinner` beside it:
        /// naming a value is the more specific instruction, which is the same rule that makes a named style
        /// win over the flag's default.
        static func spinnerValue(spinner: Bool, style: String?) -> String? {
            if style == HudSpinner.noneName { return nil }
            return style ?? (spinner ? HudSpinner.defaultStyle.rawValue : nil)
        }

        static func validateSizePercent(_ sizePercent: Int?) throws {
            if let sizePercent, !(1...100).contains(sizePercent) {
                throw ValidationError("--size-percent must be between 1 and 100")
            }
        }

        struct Open: RequestCommand {
            static let configuration = CommandConfiguration(
                abstract: "Post a message panel over the session; the session keeps focus and stays typable.")
            @Argument(help: "Message shown in the panel.") var message: String
            @Option(name: .long, help: "Dim second line under the message (e.g. what the caller is waiting on).") var detail: String?
            @Flag(name: .long, help: "Animate a spinner glyph in the panel, in the default style.")
            var spinner = false
            @Option(name: .long, help: """
                Spinner style: \(HudSpinner.acceptedNamesPhrase) \
                (default: \(HudSpinner.defaultStyle.rawValue)). Implies --spinner; \
                \(HudSpinner.noneName) leaves the panel static.
                """)
            var spinnerStyle: String?
            // the canonical nine are what `session background` shares; the aliases are this command's own,
            // so naming them in the same breath would send a caller to a --position background rejects
            @Option(name: .long, help: """
                Placement in the pane: \(HudPosition.validNamesPhrase) (default: center), the same \
                anchors session background takes. Every anchor off center holds a fixed margin at that \
                edge. Here top and bottom are also accepted, for top-center and bottom-center.
                """)
            var position: String?
            @Option(name: .long, help: "Solid background color (#rrggbb) for the panel, independent of the session's own.") var backgroundColor: String?
            @Option(name: .long, help: "Color (#rrggbb) for the panel's text; omit to keep the terminal foreground.") var textColor: String?
            @Option(name: .long, help: """
                Set the panel's WIDTH to PERCENT (1-100) of the pane instead of measuring the message; \
                bounded to \(HudLayout.minSizePercent)-\(HudLayout.maxSizePercent), so it stays readable \
                and never covers the session. Height always follows the message.
                """)
            var sizePercent: Int?
            @Option(name: .long, help: "Session (id, prefix, active; any window) a click on the panel selects, closing it; omit for an inert panel.")
            var reveal: String?
            @OptionGroup var target: TargetOptions
            @OptionGroup var options: ClientOptions

            func validate() throws {
                if let backgroundColor, !WatermarkConfig.isValidColorHex(backgroundColor) {
                    throw ValidationError("background-color must be a #rrggbb hex value")
                }
                try Hud.validateTextColor(textColor)
                try Hud.validatePosition(position)
                try Hud.validateSpinnerStyle(spinnerStyle)
                try Hud.validateSizePercent(sizePercent)
            }

            func makeRequest() throws -> ControlRequest {
                ControlRequest(cmd: .sessionHudOpen, target: target.target,
                               args: options.withWindow(ControlArgs(
                                   sizePercent: sizePercent, message: message, detail: detail,
                                   spinner: Hud.spinnerValue(spinner: spinner, style: spinnerStyle),
                                   reveal: reveal, color: backgroundColor, textColor: textColor,
                                   position: position)))
            }
        }

        /// Repaints the live panel in place. An update replaces the whole message, so every argument it
        /// accepts must be repeated to survive — including `--spinner` and `--text-color`.
        /// `--background-color` is deliberately absent: the surface reads it once at creation, so only a
        /// fresh `hud` can change it, while the text color rides the header the helper re-reads every tick.
        struct Update: RequestCommand {
            static let configuration = CommandConfiguration(
                abstract: "Replace the panel's text in place (no re-spawn, no blink).")
            @Argument(help: "New message; it replaces the old one entirely.") var message: String
            @Option(name: .long, help: "Dim second line under the message; omit to drop the old one.") var detail: String?
            @Flag(name: .long, help: "Keep (or start) the spinner in the default style; omit to stop it.")
            var spinner = false
            @Option(name: .long, help: """
                Switch the spinner to \(HudSpinner.acceptedNamesPhrase); implies --spinner, and repaints \
                the live panel without a re-spawn. \(HudSpinner.noneName) stops it.
                """)
            var spinnerStyle: String?
            @Option(name: .long, help: "Move the panel to \(HudPosition.acceptedNamesPhrase) (default: center).") var position: String?
            @Option(name: .long, help: "Recolor the panel's text (#rrggbb); omit to return it to the terminal foreground.") var textColor: String?
            @Option(name: .long, help: """
                Resize the panel's WIDTH to PERCENT (1-100) of the pane instead of measuring the message; \
                bounded to \(HudLayout.minSizePercent)-\(HudLayout.maxSizePercent), so it stays readable \
                and never covers the session. Height always follows the message.
                """)
            var sizePercent: Int?
            @Option(name: .long, help: "Session a click on the panel selects; omit to make the panel inert again.")
            var reveal: String?
            @OptionGroup var target: TargetOptions
            @OptionGroup var options: ClientOptions

            func validate() throws {
                try Hud.validateTextColor(textColor)
                try Hud.validatePosition(position)
                try Hud.validateSpinnerStyle(spinnerStyle)
                try Hud.validateSizePercent(sizePercent)
            }

            func makeRequest() throws -> ControlRequest {
                ControlRequest(cmd: .sessionHudUpdate, target: target.target,
                               args: options.withWindow(ControlArgs(
                                   sizePercent: sizePercent, message: message, detail: detail,
                                   spinner: Hud.spinnerValue(spinner: spinner, style: spinnerStyle),
                                   reveal: reveal, textColor: textColor, position: position)))
            }
        }

        struct Close: RequestCommand {
            static let configuration = CommandConfiguration(
                abstract: "Take the message panel down (a program overlay in the same slot is left alone).")
            @OptionGroup var target: TargetOptions
            @OptionGroup var options: ClientOptions

            func makeRequest() throws -> ControlRequest {
                ControlRequest(cmd: .sessionHudClose, target: target.target, args: options.withWindow())
            }
        }
    }
}
