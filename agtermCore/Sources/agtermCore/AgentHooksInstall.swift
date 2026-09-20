import Foundation
import TOMLDecoder

/// Host-free helpers for installing the agent-status hooks package: idempotent string/JSON/TOML transforms
/// returning the new contents plus a `changed` flag. Plus a mode-preserving write (`writeFile`/`posixMode`) so
/// rewriting a restrictive-mode file (e.g. a chmod-600 `settings.json`) keeps its permissions instead of an
/// atomic rename widening it to 0644. The app side owns copying the bundled scripts and resolving symlinks.
public enum AgentHooksInstall {
    /// The installed package directory's name (`~/.config/<brand>/agent-status`); a hook command
    /// under a `/agent-status/` path is ours whatever the brand or the script's name — the
    /// idempotency probe of the TOML merge.
    public static let packageName = "agent-status"

    /// The shared status wrapper every agent's hooks invoke, at the package root.
    public static let wrapperName = "agterm-agent-status.sh"

    /// The shell integration scripts sourced from the user's rc files / config.fish, relative to the script
    /// directory.
    public static let integrationRelativePath = "shell/integration.sh"
    public static let fishIntegrationRelativePath = "shell/integration.fish"

    /// Marker lines bracketing the agterm-managed block in a shell rc file or a TOML hook file; the opening
    /// marker is also the idempotency probe (present → already installed).
    public static let rcMarkerBegin = "# >>> agterm agent-status >>>"
    public static let rcMarkerEnd = "# <<< agterm agent-status <<<"

    /// Whether a plugin destination is safe to replace: absent is safe, an existing file must carry the
    /// manifest's ownership `marker`, and an unreadable one counts as user-owned — a reinstall never
    /// overwrites a user-authored integration of the same name.
    public static func mayOverwritePlugin(fileExists: Bool, existingContents: String?, marker: String) -> Bool {
        guard fileExists else { return true }
        guard let existingContents else { return false }
        return existingContents.contains(marker)
    }

    /// Thrown by `mergeJSONHooks` when the existing hook file is non-empty but not a valid JSON object: the
    /// installer refuses to overwrite a hand-maintained file it cannot safely parse.
    public enum MergeError: Error { case malformedExistingSettings }

    /// merge a profile's lifecycle hooks into its JSON settings file (`existing` nil/empty = start from a
    /// fresh object). Returns the new JSON and whether it differs; idempotent — a hook already present
    /// (detected by its script's path in an entry of that event) is skipped, so the input comes back with
    /// `changed == false` once all are in. Unrelated hooks and keys are preserved; invalid JSON throws.
    /// `dialect` picks the shape: Claude's nested entries (also Gemini's) or Cursor's flat `{command}` rows
    /// under a `version: 1` root.
    public static func mergeJSONHooks(existing: String?, scriptDir: String, dialect: HookDialect = .claude,
                                      bindings: [HookBinding]) throws -> (json: String, changed: Bool) {
        var root = try parsedObject(existing)

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var didChange = false
        for hook in bindings {
            var entries = hooks[hook.event] as? [[String: Any]] ?? []
            let script = scriptDir + "/" + hook.script
            if entries.contains(where: { entryUsesScript($0, script: script) }) {
                continue
            }
            let command = ([shellQuote(script)] + hook.args.map(shellQuoteIfNeeded)).joined(separator: " ")
            switch dialect {
            case .claude: entries.append(hookEntry(command: command, matcher: hook.matcher))
            case .cursor: entries.append(["command": command])
            }
            hooks[hook.event] = entries
            didChange = true
        }
        if !didChange {
            return (existing ?? "", false)
        }
        root["hooks"] = hooks
        if dialect == .cursor, root["version"] == nil {
            root["version"] = 1
        }
        return (serialize(root), true)
    }

    /// append the marker-guarded `source` line for the shell integration to a shell rc file.
    ///
    /// Returns the new contents and whether anything was appended; idempotent — a begin marker already present
    /// returns `existing` with `changed == false`.
    public static func appendShellRC(existing: String, scriptDir: String, scriptName: String = integrationRelativePath) -> (contents: String, changed: Bool) {
        if existing.contains(rcMarkerBegin) {
            return (existing, false)
        }
        let source = "source \(shellQuote(scriptDir + "/" + scriptName))"
        var block = rcMarkerBegin + "\n" + source + "\n" + rcMarkerEnd + "\n"
        if existing.isEmpty {
            return (block, true)
        }
        // ensure exactly one blank line between prior content and the block
        var prefix = existing
        if !prefix.hasSuffix("\n") {
            prefix += "\n"
        }
        block = "\n" + block
        return (prefix + block, true)
    }

    /// The result of merging a TOML hooks block (Codex's `~/.codex/config.toml`), decided by parsing the
    /// file with `TOMLDecoder` before touching it.
    public enum TOMLMergeOutcome: Equatable {
        /// The hooks block was added (and any stale `codex-notify.sh` notify line removed) — write `contents`.
        case merged(contents: String)
        /// The file already carries the current agterm hooks block — nothing to do.
        case unchanged
        /// The file already defines its OWN `hooks` — appending ours would duplicate (array-of-tables form) or
        /// break (compact form) them, so the merge is skipped; point the user at the docs for a manual merge.
        case hooksExist
        /// The existing file is not valid TOML — leave it untouched and point at the docs for a manual add.
        case unparseable
    }

    /// merge an agent's lifecycle hooks (`script` + `events` from its manifest) into an existing TOML config
    /// (`existing` empty = no file yet). The decision is made by PARSING with `TOMLDecoder` rather than
    /// string-matching, which is what keeps the merge safe: marker present → upgrade an older managed block to
    /// the currently installed adapter, preserving Codex's trailing hook trust-state tables, else `.unchanged`; not valid TOML →
    /// `.unparseable`; already defines `hooks` → `.hooksExist`; otherwise `.merged`, appending the
    /// marker-guarded `[[hooks.*]]` array-of-tables at end-of-file (valid because no existing `hooks` was
    /// found) and removing a stale top-level `notify` ONLY when its PARSED value points at the retired
    /// `codex-notify.sh`, so a comment merely naming the file, or the user's own notifier, is never touched.
    /// The surgical append/removal preserves the user's comments and layout.
    public static func mergeTOMLHooks(existing: String, scriptDir: String, script: String,
                                      events: [TOMLHookEvent]) -> TOMLMergeOutcome {
        let block = tomlHooksBlock(scriptDir: scriptDir, script: script, events: events)
        // marker present → refresh only our managed hook definitions. Codex may append hook trust-state
        // tables before our end marker; the refresh preserves that suffix byte-for-byte.
        if existing.contains(rcMarkerBegin) {
            let refreshed = refreshManagedBlock(in: existing, with: block)
            return refreshed == existing ? .unchanged : .merged(contents: refreshed)
        }

        // a genuinely empty/whitespace file has no TOML to parse — start fresh.
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .merged(contents: appendBlock(block, to: existing))
        }

        // parse to make the merge decisions structurally; a parse failure means don't rewrite it.
        guard let probe = try? TOMLDecoder().decode(CodexConfigProbe.self, from: existing) else {
            return .unparseable
        }
        if probe.hooksPresent {
            return .hooksExist
        }

        var text = existing
        if probe.notify.contains(where: { $0.contains("codex-notify.sh") }) {
            text = removeLegacyCodexNotify(from: text)
        }
        return .merged(contents: appendBlock(block, to: text))
    }

    // the two top-level keys the merge cares about (Codable ignores every other). `hooksPresent` is a presence
    // check across any hooks shape; `notify` is the top-level notify program (array-of-argv or a bare string),
    // so the retired codex-notify.sh is recognized by its PARSED value, not a fragile line match.
    private struct CodexConfigProbe: Decodable {
        let hooksPresent: Bool
        let notify: [String]

        private enum CodingKeys: String, CodingKey { case hooks, notify }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hooksPresent = container.contains(.hooks)
            if let array = try? container.decodeIfPresent([String].self, forKey: .notify) {
                notify = array
            } else if let single = try? container.decodeIfPresent(String.self, forKey: .notify) {
                notify = [single]
            } else {
                notify = []
            }
        }
    }

    // append the marker-guarded hooks block, one blank line after any prior content.
    private static func appendBlock(_ definitions: String, to text: String) -> String {
        let block = rcMarkerBegin + "\n" + definitions + "\n" + rcMarkerEnd + "\n"
        if text.isEmpty { return block }
        var prefix = text
        if !prefix.hasSuffix("\n") { prefix += "\n" }
        return prefix + "\n" + block
    }

    // replace only the generated definitions inside an existing managed block. Codex writes its
    // `[hooks.state...]` trust records at the end of config.toml, landing inside our EOF marker, so retain that
    // suffix. A coincidental marker block invoking nothing from an agent-status package is foreign and left
    // untouched.
    private static func refreshManagedBlock(in text: String, with definitions: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == rcMarkerBegin }),
              let end = lines.indices.dropFirst(begin + 1).first(where: {
                  lines[$0].trimmingCharacters(in: .whitespaces) == rcMarkerEnd
              }) else { return text }
        let body = lines[(begin + 1)..<end]
        guard body.contains(where: { $0.contains("/" + packageName + "/") }) else {
            return text
        }

        var suffix: [String] = []
        if var stateStart = body.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("[hooks.state")
        }) {
            if stateStart > begin + 1, lines[stateStart - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                stateStart -= 1
            }
            suffix = Array(lines[stateStart..<end])
        }

        var replacement = definitions.components(separatedBy: "\n")
        if !suffix.isEmpty {
            if suffix.first?.trimmingCharacters(in: .whitespaces).isEmpty == false { replacement.append("") }
            replacement.append(contentsOf: suffix)
        }
        lines.replaceSubrange((begin + 1)..<end, with: replacement)
        return lines.joined(separator: "\n")
    }

    // remove the retired single-line `notify = [...codex-notify.sh...]` — only the old installer wrote that
    // form, and the caller already confirmed the parsed value. Restricted to the TOP-LEVEL region (above the
    // first table header), so a table-scoped notify is untouched, and to codex-notify.sh in the VALUE, so a
    // hand-authored multi-line array isn't half-removed.
    private static func removeLegacyCodexNotify(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let limit = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        guard let idx = lines[..<limit].firstIndex(where: { line in
            guard line.contains("codex-notify.sh"), let eq = line.firstIndex(of: "=") else { return false }
            return line[..<eq].trimmingCharacters(in: .whitespaces) == "notify"
        }) else { return text }
        lines.remove(at: idx)
        return lines.joined(separator: "\n")
    }

    /// derive a backup path by appending `.bak` to the full path, extension intact (`settings.json.bak`).
    public static func backupPath(for path: String) -> String {
        path + ".bak"
    }

    /// the absolute wrapper-script path the installed hooks invoke (`<scriptDir>/agterm-agent-status.sh`); the
    /// caller's hook entry appends the state.
    public static func wrapperPath(scriptDir: String) -> String {
        scriptDir + "/" + wrapperName
    }

    /// render the `[[hooks.*]]` block the installer merges into a TOML config, wiring the agent's lifecycle
    /// events to its adapter `script`. `site/docs.html#codex-hooks-manual` reproduces Codex's block for the
    /// cases the merge declines, and nothing checks the two against each other.
    /// The adapter's absolute path is baked into each command — shell-quoted (so a path with spaces stays one
    /// token) inside a TOML basic string — so the hook fires without the CLI on PATH.
    public static func tomlHooksBlock(scriptDir: String, script: String, events: [TOMLHookEvent]) -> String {
        let wrapper = shellQuote(scriptDir + "/" + script)
        return events.map { hook in
            """
            [[hooks.\(hook.event)]]
            [[hooks.\(hook.event).hooks]]
            type = "command"
            command = \(tomlBasicString(wrapper + " " + hook.action))
            """
        }.joined(separator: "\n\n")
    }

    /// the POSIX permission bits of the file at `path`, or nil when it is absent or unreadable — captured
    /// before a mode-preserving rewrite.
    public static func posixMode(ofFile path: String) -> NSNumber? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.posixPermissions] as? NSNumber
    }

    /// write `text` to `path` atomically, then re-apply `posixMode` when non-nil: the atomic write renames a
    /// fresh 0644 temp over the target, which would otherwise widen a restrictive mode (e.g. a chmod-600
    /// secret). A nil `posixMode` leaves the new file's default permissions.
    public static func writeFile(_ text: String, toPath path: String, posixMode: NSNumber?) throws {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        if let posixMode {
            try FileManager.default.setAttributes([.posixPermissions: posixMode], ofItemAtPath: path)
        }
    }

    // a single Claude hook entry: { (matcher?), hooks: [{ type: command, command }] }.
    private static func hookEntry(command: String, matcher: String?) -> [String: Any] {
        var entry: [String: Any] = [
            "hooks": [["type": "command", "command": command]],
        ]
        if let matcher {
            entry["matcher"] = matcher
        }
        return entry
    }

    // does a hook entry already invoke this script (idempotency probe, by absolute script path)?
    private static func entryUsesScript(_ entry: [String: Any], script: String) -> Bool {
        if (entry["command"] as? String)?.contains(script) == true { return true }
        guard let commands = entry["hooks"] as? [[String: Any]] else { return false }
        return commands.contains { ($0["command"] as? String)?.contains(script) == true }
    }

    // absent/empty/whitespace-only → fresh empty object; a non-empty file that is not a valid JSON object →
    // throw rather than silently discard the user's file.
    private static func parsedObject(_ text: String?) throws -> [String: Any] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let data = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let object = parsed as? [String: Any] else {
            throw MergeError.malformedExistingSettings
        }
        return object
    }

    // serialize a dictionary to pretty-printed, sorted JSON text (deterministic for tests + diffs).
    private static func serialize(_ object: [String: Any]) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text + "\n"
    }

    // single-quote a string for safe embedding in a /bin/sh command (mirrors CLIInstall.shellQuote).
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // quote only what the shell would otherwise split or expand, so a hook line reads `active --blink`
    // rather than `'active' '--blink'` and a resume template with spaces stays one argument.
    static func shellQuoteIfNeeded(_ value: String) -> String {
        let plain = value.allSatisfy { $0.isLetter || $0.isNumber || "-_./=:@,+%".contains($0) }
        return plain && !value.isEmpty ? value : shellQuote(value)
    }

    // quote a string as a TOML basic (double-quoted) string: escape backslash then double-quote so an
    // arbitrary shell command embeds safely as a config.toml value (the Codex hook `command` field).
    private static func tomlBasicString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
