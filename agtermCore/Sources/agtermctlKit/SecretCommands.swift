import ArgumentParser
import Foundation
import agtermCore

/// `agtermctl secret list|add|remove|insert` — the login-keychain secrets the Insert Secret palette types.
/// The value enters ONLY through `add`'s stdin (a hidden prompt on a tty, the whole stream otherwise) so it
/// never sits in `ps` output or shell history, and no command reads it back.
struct Secret: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Store secrets in the keychain and type them into a session without echoing them.",
        subcommands: [List.self, Add.self, Remove.self, Insert.self]
    )

    struct List: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "List stored secret labels.")
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .secretList)
        }
    }

    struct Add: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Store a secret under a label, replacing an existing one. The value is read from stdin: "
                + "a hidden prompt on a terminal, otherwise the piped text minus one trailing newline."
        )
        @Argument(help: "Label the palette lists (max \(SecretPolicy.maxLabelLength) characters).") var label: String
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            guard let value = Secret.readValue(label: label) else {
                throw ValidationError("no value read from stdin")
            }
            return request(value: value)
        }

        func request(value: String) -> ControlRequest {
            ControlRequest(cmd: .secretAdd, args: ControlArgs(label: label, value: value))
        }
    }

    struct Remove: RequestCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a stored secret.")
        @Argument(help: "Label of the secret to delete.") var label: String
        @OptionGroup var options: BasicOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .secretRemove, args: ControlArgs(label: label))
        }
    }

    struct Insert: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Type a stored secret into a session, like `session type` but without the value on the command line."
        )
        @Argument(help: "Label of the secret to type.") var label: String
        @OptionGroup var target: TargetOptions
        @Option(name: .long, help: "Pane to type into: left (default), right, or scratch.")
        var pane: String?
        @OptionGroup var options: ClientOptions

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .secretInsert, target: target.target,
                           args: options.withWindow(ControlArgs(pane: pane, label: label)))
        }
    }

    /// The value from stdin: on a tty, one line typed at a hidden prompt; otherwise the whole stream with a
    /// single trailing newline stripped, so `printf '%s' pw |` and `echo pw |` both store `pw`.
    static func readValue(label: String) -> String? {
        if isatty(STDIN_FILENO) == 1 {
            return readHidden(prompt: "Secret for \(label): ")
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        var text = String(decoding: data, as: UTF8.self)
        if text.hasSuffix("\n") { text.removeLast() }
        if text.hasSuffix("\r") { text.removeLast() }
        return text.isEmpty ? nil : text
    }

    private static func readHidden(prompt: String) -> String? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var hidden = original
        hidden.c_lflag &= ~tcflag_t(ECHO)
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &hidden) == 0 else { return nil }
        defer { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) }
        FileHandle.standardError.write(Data(prompt.utf8))
        let line = readLine(strippingNewline: true)
        FileHandle.standardError.write(Data("\n".utf8))
        guard let line, !line.isEmpty else { return nil }
        return line
    }
}
