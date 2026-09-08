import AppKit
import agtermCore

/// Installs the bundled command-line tools into the user's PATH by symlinking them from the app bundle into
/// `/usr/local/bin`: `agtermctl` (`Contents/MacOS`) and `agx` (`Contents/Resources`, a python3 script).
/// Direct symlinks when the dir is user-writable (no prompt), else ONE GUI admin prompt via `osascript`
/// covering every link (a clean Apple Silicon Mac has a root-owned `/usr/local/bin`). Host-free path/command
/// logic is `agtermCore.CLIInstall`; this owns the AppKit filesystem + authorization glue.
@MainActor
enum CLIInstaller {
    enum InstallResult {
        case installed(links: [CLIInstall.Link])
        case failed(String)
        case cancelled
    }

    /// The bundled helper at `Contents/MacOS/agtermctl`, or nil when this build skipped the bundling phase
    /// (e.g. a bare `swift build`).
    static var bundledTool: URL? { Bundle.main.url(forAuxiliaryExecutable: CLIInstall.toolName) }

    /// The bundled `agx` at `Contents/Resources/agx`, or nil when this build did not copy it.
    static var bundledAgx: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(CLIInstall.agxName),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    /// Run the install and show a result alert (a cancelled admin prompt shows nothing).
    static func run() {
        switch install() {
        case .installed(let links):
            let names = CLIInstall.describe(links)
            present(style: .informational, title: "Command Line Tools Installed",
                    text: "\(names) were linked into \(CLIInstall.installDirectory). "
                        + "Open a new terminal and run “agtermctl --help” or “agx context”.")
        case .failed(let message):
            present(style: .warning, title: "Install Failed", text: message)
        case .cancelled:
            break
        }
    }

    private static func install() -> InstallResult {
        guard let tool = bundledTool?.path else {
            return .failed("\(CLIInstall.toolName) is not bundled in this build.")
        }
        guard let agx = bundledAgx?.path else {
            return .failed("\(CLIInstall.agxName) is not bundled in this build.")
        }
        let links = [
            CLIInstall.Link(source: tool, name: CLIInstall.toolName),
            CLIInstall.Link(source: agx, name: CLIInstall.agxName),
        ]
        if links.allSatisfy(directSymlink) { return .installed(links: links) }
        return elevatedSymlink(links: links)
    }

    /// Replace any existing link and symlink the bundled tool into place. Succeeds only when the target
    /// directory is user-writable; any error (typically a root-owned dir) returns false so the caller
    /// escalates.
    private static func directSymlink(_ link: CLIInstall.Link) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(atPath: link.installPath)
        do {
            try fm.createSymbolicLink(atPath: link.installPath, withDestinationPath: link.source)
            return true
        } catch {
            return false
        }
    }

    /// Create every symlink through a single GUI admin prompt. Returns `.cancelled` when the user dismisses
    /// the authorization dialog (AppleScript error -128).
    private static func elevatedSymlink(links: [CLIInstall.Link]) -> InstallResult {
        let command = CLIInstall.privilegedInstallCommand(links: links)
        let apple = "do shell script \(appleScriptString(command)) with administrator privileges"
        guard let script = NSAppleScript(source: apple) else {
            return .failed("Could not build the install script.")
        }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        guard let err else { return .installed(links: links) }
        if (err[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled } // user dismissed the prompt
        return .failed((err[NSAppleScript.errorMessage] as? String) ?? "Authorization failed.")
    }

    private static func present(style: NSAlert.Style, title: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    /// Quote a string as an AppleScript string literal.
    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
