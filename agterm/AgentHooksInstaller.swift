import AppKit
import SwiftUI
import agtermCore

/// Installs the bundled agent-status package into the user's home: the scripts into
/// `~/.config/<brand>/agent-status/`, the bundled `agtermctl`/`agx` absolute paths baked into every shell
/// script that resolves them, a marker-guarded `source` line in `~/.zshrc`/`~/.bashrc`/
/// `~/.config/fish/config.fish`, and then one step per agent manifest (`agents/<binary>/agent.json`) by its
/// `status.kind`: JSON hooks merged into the agent's hook file, a TOML `[[hooks.*]]` block into its config,
/// or a plugin copied into its plugins directory — each only when the agent's own directory already exists.
/// Hook files get a `.bak` first; a TOML step that finds foreign hooks or no parseable TOML points at the
/// docs for a manual merge. The result is one row per agent (`AgentHooksResultView`). The host-free string/JSON/TOML transforms and the plugin ownership policy live in
/// `agtermCore.AgentHooksInstall`; this type owns the AppKit filesystem glue. Idempotent: a re-run refreshes
/// the baked tool paths (healing a moved bundle) and no-ops on already-present entries.
@MainActor
enum AgentHooksInstaller {
    private struct InstallError: Error { let message: String }

    /// The bundled `Contents/Resources/agent-status`, nil when the build skipped bundling (a bare
    /// `swift build`).
    private static var bundledFolder: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("agent-status")
    }

    /// The bundled `agtermctl` at `Contents/MacOS/agtermctl`, or nil when this build skipped bundling.
    private static var bundledTool: URL? { Bundle.main.url(forAuxiliaryExecutable: CLIInstall.toolName) }

    private static var destinationFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/\(Brand.configDirectoryName)/agent-status")
    }

    /// The outcome of one agent's install step, whatever its integration kind.
    enum IntegrationResult: Equatable {
        /// The hooks were merged or the plugin written.
        case merged
        /// Already current — nothing to do.
        case unchanged
        /// The agent's directory does not exist, so nothing was seeded.
        case notInstalled
        /// The file was left untouched; `reason` completes "Your ~/<file> <reason>". `manual` sends the user
        /// to the docs for a hand merge (a TOML config with its own hooks, or one that does not parse).
        case skipped(reason: String, manual: Bool)

        var isWarning: Bool {
            if case .skipped = self { return true }
            return false
        }

        var needsManualMerge: Bool {
            if case .skipped(_, let manual) = self { return manual }
            return false
        }
    }

    /// One agent's line in the result window: the profile (name, tile) and what happened to it.
    struct Row {
        let profile: AgentProfile
        let result: IntegrationResult

        /// The one-liner under the name. No paths: the file is named only when it was left untouched,
        /// and then by its basename, so the user knows WHICH file to look at without a column of homes.
        var detail: String {
            switch result {
            case .merged:
                return [installed, profile.activate].compactMap { $0 }.joined(separator: " ")
            case .unchanged:
                return "Already set up."
            case .notInstalled:
                return "Not installed on this Mac."
            case .skipped(let reason, let manual):
                return "\(targetName) \(reason) — left untouched." + (manual ? " See the docs for the block to add by hand." : "")
            }
        }

        private var installed: String {
            if case .plugin = profile.status { return "Plugin installed." }
            return "Hooks added."
        }

        private var targetName: String {
            switch profile.status {
            case .jsonHooks(let file, _, _), .tomlHooks(let file, _, _): return (file as NSString).lastPathComponent
            case .plugin(_, let destination, _, _): return (destination as NSString).lastPathComponent
            case .none: return ""
            }
        }
    }

    /// Run the install and show the result window.
    static func run() {
        do {
            let rows = try install()
            let docs = rows.contains { $0.result.needsManualMerge } ? codexManualDocsURL : nil
            presentResult(rows: rows, docs: docs)
        } catch let error as InstallError {
            present(style: .warning, title: "Install Failed", text: error.message)
        } catch {
            present(style: .warning, title: "Install Failed", text: error.localizedDescription)
        }
    }

    // every step runs regardless of an earlier one's outcome; each agent reports its own result.
    private static func install() throws -> [Row] {
        try copyBundledFolder()
        try bakeToolPaths()
        try appendShellRC()
        return try AgentCatalog.known.filter(\.hasStatusIntegration).map { Row(profile: $0, result: try install($0)) }
    }

    private static func install(_ profile: AgentProfile) throws -> IntegrationResult {
        switch profile.status {
        case .jsonHooks(let file, let dialect, let hooks):
            return try mergeJSONHooks(profile, file: file, dialect: dialect, bindings: hooks)
        case .tomlHooks(let file, let script, let events):
            return try mergeTOMLHooks(profile, file: file, script: script, events: events)
        case .plugin(let source, let destination, let requires, let marker):
            return try installPlugin(source: source, destination: destination, requires: requires, marker: marker)
        case .none:
            return .unchanged
        }
    }

    private static func copyBundledFolder() throws {
        guard let source = bundledFolder, FileManager.default.fileExists(atPath: source.path) else {
            throw InstallError(message: "The agent-status scripts are not bundled in this build.")
        }
        let fm = FileManager.default
        let destination = destinationFolder
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: destination) // drop a prior install so copy can't collide
        try fm.copyItem(at: source, to: destination)
    }

    // sentinel for the installer-baked tool-path defaults, so a reader knows the lines are generated.
    private static let bakedMarker = "# >>> agterm tool paths (installer-baked) >>>"

    // bake the bundled tools' absolute paths into every installed shell script that resolves them
    // (`${AGTERMCTL:-agtermctl}`, `${AGX:-…}`), so the hooks fire even when the CLIs were never symlinked
    // into PATH. `[ -n "${VAR:-}" ] ||` assigns only when unset, so an explicit env override still wins
    // (order 1 > 2 > PATH); shellQuote keeps spaces / metacharacters inert. The package was just copied
    // fresh, so there is never a prior block to strip.
    private static func bakeToolPaths() throws {
        let tools: [(variable: String, path: String?)] = [
            ("AGTERMCTL", bundledTool?.path),
            ("AGX", CLIInstaller.bundledAgx?.path),
        ]
        let fm = FileManager.default
        guard let files = fm.enumerator(at: destinationFolder, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in files where file.pathExtension == "sh" {
            let original = try String(contentsOf: file, encoding: .utf8)
            let lines = tools.compactMap { tool -> String? in
                guard let path = tool.path, original.contains("${\(tool.variable):-") else { return nil }
                return "[ -n \"${\(tool.variable):-}\" ] || \(tool.variable)=\(AgentHooksInstall.shellQuote(path))"
            }
            guard !lines.isEmpty else { continue }
            let baked = insertAfterShebang(original, block: ([bakedMarker] + lines).joined(separator: "\n") + "\n")
            try writePreservingSymlink(baked, to: file)
        }
    }

    private static func insertAfterShebang(_ text: String, block: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let insertAt = lines.first?.hasPrefix("#!") == true ? 1 : 0
        lines.insert(contentsOf: block.components(separatedBy: "\n").dropLast(), at: insertAt)
        return lines.joined(separator: "\n")
    }

    // write text PRESERVING an existing symlink: a dotfiles-managed link (`~/.claude/settings.json`,
    // `~/.zshrc`) is written through to its resolved target, since an atomic rename would replace the link
    // with a regular file. `posixMode` applies to that target, so a chmod-600 file isn't widened.
    private static func writePreservingSymlink(_ text: String, to url: URL, posixMode: NSNumber? = nil) throws {
        let target = symlinkTarget(of: url) ?? url
        try AgentHooksInstall.writeFile(text, toPath: target.path, posixMode: posixMode)
    }

    // the resolved target if `url` is itself a symlink (chain followed), else nil. detection uses
    // `attributesOfItem`, which does NOT follow the final link.
    private static func symlinkTarget(of url: URL) -> URL? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeSymbolicLink else { return nil }
        return url.resolvingSymlinksInPath()
    }

    // read an existing config file: nil when ABSENT (a fresh install), the contents when readable, a thrown
    // `UnreadableExisting` when it EXISTS but can't be read (permission / non-UTF8) — so callers leave it
    // untouched instead of clobbering it with no backup.
    private struct UnreadableExisting: Error {}
    private static func readExistingConfig(at url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw UnreadableExisting()
        }
    }

    // write a config file through its symlink with the target's mode, backing up the prior contents beside
    // the link first (NOT beside the resolved target, which may be a git-tracked dotfiles dir we must not
    // litter; only the MODE comes from the target).
    private static func writeConfig(_ contents: String, to url: URL, backingUp existing: String?) throws {
        let target = symlinkTarget(of: url) ?? url
        let mode = AgentHooksInstall.posixMode(ofFile: target.path)
        if let existing, !existing.isEmpty {
            try AgentHooksInstall.writeFile(existing, toPath: AgentHooksInstall.backupPath(for: url.path), posixMode: mode)
        }
        try writePreservingSymlink(contents, to: url, posixMode: mode)
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appendingPathComponent(relative).path)
    }

    // merge a profile's hooks into its JSON hook file. Gated on the agent's config directory existing so a
    // home without the agent isn't seeded with its settings file.
    private static func mergeJSONHooks(_ profile: AgentProfile, file: String, dialect: HookDialect,
                                       bindings: [HookBinding]) throws -> IntegrationResult {
        guard let configDirectory = profile.configDirectory, exists(configDirectory) else { return .notInstalled }
        let settings = home.appendingPathComponent(file)
        let existing: String?
        do {
            existing = try readExistingConfig(at: settings)
        } catch {
            return .skipped(reason: "exists but couldn't be read", manual: false)
        }
        let merged: (json: String, changed: Bool)
        do {
            merged = try AgentHooksInstall.mergeJSONHooks(existing: existing, scriptDir: destinationFolder.path,
                                                          dialect: dialect, bindings: bindings)
        } catch AgentHooksInstall.MergeError.malformedExistingSettings {
            return .skipped(reason: "isn't valid JSON", manual: false)
        }
        guard merged.changed else { return .unchanged }
        try writeConfig(merged.json, to: settings, backingUp: existing)
        return .merged
    }

    // merge a profile's `[[hooks.*]]` block into its TOML config. The host-free
    // `AgentHooksInstall.mergeTOMLHooks` PARSES the file and decides the outcome; this only reads/writes.
    private static func mergeTOMLHooks(_ profile: AgentProfile, file: String, script: String,
                                       events: [TOMLHookEvent]) throws -> IntegrationResult {
        guard let configDirectory = profile.configDirectory, exists(configDirectory) else { return .notInstalled }
        let config = home.appendingPathComponent(file)
        let existing: String?
        do {
            existing = try readExistingConfig(at: config)
        } catch {
            return .skipped(reason: "exists but couldn't be read", manual: false)
        }
        switch AgentHooksInstall.mergeTOMLHooks(existing: existing ?? "", scriptDir: destinationFolder.path,
                                                script: script, events: events) {
        case .unchanged:
            return .unchanged
        case .hooksExist:
            return .skipped(reason: "already defines its own hooks", manual: true)
        case .unparseable:
            return .skipped(reason: "isn't valid TOML — fix it and run this again", manual: true)
        case .merged(let contents):
            try writeConfig(contents, to: config, backingUp: existing)
            return .merged
        }
    }

    // copy a bundled plugin into the agent's auto-discovered plugins directory, only once `requires` exists.
    // an UNMARKED same-named file is user-owned and left untouched; a marked one refreshes from the copied
    // package. no backup, unlike the hook files: the plugin carries no user state.
    private static func installPlugin(source: String, destination: String, requires: String,
                                      marker: String) throws -> IntegrationResult {
        guard exists(requires) else { return .notInstalled }
        let sourceURL = destinationFolder.appendingPathComponent(source)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw InstallError(message: "\(source) is not bundled in this build.")
        }
        let contents = try String(contentsOf: sourceURL, encoding: .utf8)
        guard contents.contains(marker) else {
            throw InstallError(message: "The bundled \(source) is missing its ownership marker.")
        }
        let target = home.appendingPathComponent(destination)
        // nil = absent, throw = exists-but-unreadable: a non-ENOENT stat error must not masquerade as
        // "absent" and slip past the ownership-marker gate.
        let existing: String?
        do {
            existing = try readExistingConfig(at: target)
        } catch {
            return .skipped(reason: "exists but couldn't be read", manual: false)
        }
        guard AgentHooksInstall.mayOverwritePlugin(fileExists: existing != nil, existingContents: existing,
                                                   marker: marker) else {
            return .skipped(reason: "is user-owned", manual: false)
        }
        guard existing != contents else { return .unchanged }
        // a filesystem error degrades to a warning like every sibling integration, rather than aborting the
        // whole install and hiding that the other steps ran.
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let mode = AgentHooksInstall.posixMode(ofFile: (symlinkTarget(of: target) ?? target).path)
            try writePreservingSymlink(contents, to: target, posixMode: mode)
        } catch {
            return .skipped(reason: "couldn't be written (check the directory's permissions)", manual: false)
        }
        return .merged
    }

    // append the marker-guarded source line to ~/.zshrc, ~/.bashrc, ~/.config/fish/config.fish (idempotent).
    private static func appendShellRC() throws {
        for name in [".zshrc", ".bashrc", ".config/fish/config.fish"] {
            let rc = home.appendingPathComponent(name)
            if name.hasSuffix(".fish") {
                // only touch config.fish when the user already has a ~/.config/fish directory
                guard FileManager.default.fileExists(atPath: rc.deletingLastPathComponent().path) else { continue }
            }
            let existing = (try? String(contentsOf: rc, encoding: .utf8)) ?? ""
            let scriptName = name.hasSuffix(".fish") ? AgentHooksInstall.fishIntegrationRelativePath : AgentHooksInstall.integrationRelativePath
            let result = AgentHooksInstall.appendShellRC(existing: existing, scriptDir: destinationFolder.path, scriptName: scriptName)
            guard result.changed else { continue }
            try writePreservingSymlink(result.contents, to: rc)
        }
    }

    // the result window, run modally like the alert it replaces so the callers' queueing (welcome →
    // skill → hooks) keeps working.
    private static func presentResult(rows: [Row], docs: URL?) {
        let holder = WindowHolder()
        let view = AgentHooksResultView(rows: rows, docs: docs, onOpenDocs: {
            if let docs { NSWorkspace.shared.open(docs) }
            holder.close()
        }, onClose: { holder.close() })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = "Agent Status Hooks"
        window.center()
        holder.window = window
        NSApp.runModal(for: window)
    }

    @MainActor
    private final class WindowHolder {
        var window: NSWindow?

        func close() {
            guard let window else { return }
            self.window = nil
            NSApp.stopModal()
            window.close()
        }
    }

    /// The docs anchor covering a manual Codex hooks merge, opened by the alert's second button. An NSAlert
    /// renders `informativeText` as plain, unselectable text, so a printed URL would have to be retyped.
    static let codexManualDocsURL = URL(string: "https://agterm.com/docs#codex-hooks-manual")

    // the install-failed alert: the package could not even be copied, so there are no rows to show.
    private static func present(style: NSAlert.Style, title: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
