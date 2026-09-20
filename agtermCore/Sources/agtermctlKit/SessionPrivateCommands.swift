import ArgumentParser
import Foundation
import agtermCore

extension Session {
    // `PrivateCommand` for the same reason `FlagCommand` is not `Flag`: `private` is a keyword.
    struct PrivateCommand: RequestCommand {
        static let configuration = CommandConfiguration(
            commandName: "private",
            abstract: "Mark a session private (on|off|toggle): never persisted; its agent's files are erased on close.")
        @Argument(help: "Mode: on, off, or toggle (default).") var mode: String = "toggle"
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws {
            guard ["on", "off", "toggle"].contains(mode) else {
                throw ValidationError("mode must be on, off, or toggle")
            }
        }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .sessionPrivate, target: target.target, args: options.withWindow(ControlArgs(mode: mode)))
        }
    }
}
