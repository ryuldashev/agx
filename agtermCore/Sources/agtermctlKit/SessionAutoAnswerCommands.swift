import ArgumentParser
import Foundation
import agtermCore

// MARK: - session autoanswer

/// In its own file, like `Failure`, because `SessionCommands.swift` sits at the length limits.
extension Session {
    /// Per-session switch for auto-answer: whether a `blocked` permission prompt in this session is answered
    /// by the app after the Settings grace. `status` (the default) only reads.
    struct AutoAnswer: RequestCommand {
        static let configuration = CommandConfiguration(
            commandName: "autoanswer",
            abstract: "Turn auto-answer on or off for a session, or read its state.",
            discussion: """
            session autoanswer status --target ID   on (settings) 45s
            session autoanswer off --target ID      this session keeps its prompts for the user
            session autoanswer on --target ID       back to answering after the grace

            With auto-answer on, a session left `blocked` on a permission prompt for the Settings ▸ Agents \
            grace (default 45 s) gets the affirmative key from the app: Return for Claude Code, y for Codex. \
            A prompt showing a destructive command (rm -rf, git push --force, sudo, git reset --hard, DROP …) \
            is never answered — the app notifies instead. `on`/`off` set this session's override; the \
            answer reports the effective state, its source (session|settings), the delay, a running grace \
            (`due`) and the last decision.
            """)
        @Argument(help: "on, off or status (default: status).") var mode: String = "status"
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws {
            guard ["on", "off", "status"].contains(mode) else {
                throw ValidationError("mode must be on, off or status")
            }
        }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .sessionAutoAnswer, target: target.target,
                           args: options.withWindow(ControlArgs(mode: mode)))
        }
    }
}
