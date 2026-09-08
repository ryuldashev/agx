/// Pure, host-free helpers for installing the bundled command-line tools (`agtermctl`, `agx`) into the
/// user's PATH — only the testable string/path logic. The app side does the filesystem work: symlinks, with
/// an `osascript` admin fallback when the target dir isn't user-writable.
public enum CLIInstall {
    /// The control CLI's executable name, bundled at `Contents/MacOS/agtermctl`.
    public static let toolName = "agtermctl"

    /// The agent-facing `agx` CLI's name, bundled at `Contents/Resources/agx`. A python3 script, so it lives
    /// in Resources rather than beside the Mach-O helper; it finds `agtermctl` as `../MacOS/agtermctl`.
    public static let agxName = "agx"

    /// The PATH directory the tools are installed into. `/usr/local/bin` is the first entry in macOS's
    /// default `/etc/paths`, so it's on every user's PATH out of the box (unlike `~/.local/bin`).
    public static let installDirectory = "/usr/local/bin"

    /// The full symlink path an install creates for `agtermctl`.
    public static var installPath: String { installPath(for: toolName) }

    /// The full symlink path an install creates for the tool named `name`.
    public static func installPath(for name: String) -> String {
        installDirectory + "/" + name
    }

    /// One symlink an install creates: the bundled `source` linked as `installDirectory/name`.
    public struct Link: Equatable, Sendable {
        public let source: String
        public let name: String

        public init(source: String, name: String) {
            self.source = source
            self.name = name
        }

        public var installPath: String { CLIInstall.installPath(for: name) }
    }

    /// The shell command creating every symlink in `links` with elevated privileges, run via `osascript …
    /// with administrator privileges` when `installDirectory` isn't user-writable — one prompt for all of
    /// them. Creates the directory first (a clean Apple Silicon Mac may lack it) and overwrites any existing
    /// link.
    public static func privilegedInstallCommand(links: [Link]) -> String {
        let commands = ["mkdir -p \(shellQuote(installDirectory))"]
            + links.map { "ln -sf \(shellQuote($0.source)) \(shellQuote($0.installPath))" }
        return commands.joined(separator: " && ")
    }

    /// The names in `links`, joined for an alert: `agtermctl and agx`.
    public static func describe(_ links: [Link]) -> String {
        let names = links.map(\.name)
        guard names.count > 1 else { return names.joined() }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// Single-quote a string for safe embedding in a `/bin/sh` command.
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
