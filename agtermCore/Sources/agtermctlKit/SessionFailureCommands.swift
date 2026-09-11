import ArgumentParser
import Foundation
import agtermCore

// MARK: - session failure

/// In its own file, like `Reader`, because `SessionCommands.swift` sits at the length limits.
extension Session {
    /// The agent's failure report. Claude Code's `StopFailure` hook calls this with the hook's `error`
    /// type and `last_assistant_message`; the app then switches the pane's model, retries, hands the task
    /// to another agent, or just tells the user — and answers which it did.
    struct Failure: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report an agent failure in a session so the app can switch models or hand the task to another agent.",
            discussion: """
            session failure rate_limit --message "You're out of usage credits…"   let the app decide
            session failure rate_limit --handoff                                   hand off to another agent now

            ERROR is the agent's error type (rate_limit, overloaded, server_error, authentication_failed, …); \
            --message is the text it showed, which decides whether a model's pool or the whole account ran \
            dry. The answer names the action: switch-model (with the /model argument), retry, handoff (with \
            the new session's id) or notify.
            """)
        @Argument(help: "The agent's error type, e.g. rate_limit.") var error: String
        @Option(name: .long, help: "The error text the agent showed.") var message: String?
        @Option(name: .long, help: "The agent's transcript file, so a handoff can carry the conversation.") var transcript: String?
        @Flag(name: .long, help: "Skip the model ladder and hand the task to another agent now.") var handoff = false
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            let path = transcript.map(Reader.absolutePath)
            return ControlRequest(cmd: .sessionFailure, target: target.target,
                                  args: options.withWindow(ControlArgs(message: message, error: error,
                                                                        transcript: path,
                                                                        handoff: handoff ? true : nil)))
        }
    }
}
