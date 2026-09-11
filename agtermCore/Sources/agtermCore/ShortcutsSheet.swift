import Foundation

/// Renders the live keymap as the "Keyboard Shortcuts" markdown sheet the reader panel shows. Host-free so
/// it is unit-testable and shares one source of truth with the menu and palette: every chord comes from the
/// same `Keymap.equivalent`/`sequences` the menu resolves, so a rebind in `keymap.conf` moves the sheet too.
///
/// One action per row, keys as `<kbd>` capsules (`reader.css` styles them and right-aligns the Keys column).
/// The grouping mirrors the action palette's taxonomy; the label copy is the sheet's own, so a context-only
/// palette title ("Flag / Unflag") reads as one stable line here.
public enum ShortcutsSheet {
    /// One labelled built-in row.
    private struct Row { let action: BuiltinAction; let label: String }

    /// A titled group of rows, with an optional one-line note under the heading.
    private struct Group { let title: String; let note: String?; let rows: [Row] }

    /// The full taxonomy. Every `BuiltinAction` appears exactly once, pinned by `ShortcutsSheetTests`, so a
    /// new action fails a test until it is placed here rather than dropping silently off the sheet.
    private static let groups: [Group] = [
        Group(title: "Sessions", note: "A session is one shell in the sidebar.", rows: [
            Row(action: .newSession, label: "New session"),
            Row(action: .openDirectory, label: "New session in a directory…"),
            Row(action: .renameSession, label: "Rename session"),
            Row(action: .duplicateSession, label: "Duplicate session"),
            Row(action: .closeSession, label: "Close session"),
            Row(action: .reopenRecent, label: "Reopen last closed"),
            Row(action: .undoClose, label: "Reopen a closed session"),
            Row(action: .clearStatus, label: "Clear status glyph"),
        ]),
        Group(title: "Move between sessions", note: "Step through the sidebar without the mouse.", rows: [
            Row(action: .previousSession, label: "Previous session"),
            Row(action: .nextSession, label: "Next session"),
            Row(action: .firstSession, label: "First session"),
            Row(action: .lastSession, label: "Last session"),
            Row(action: .previousAttentionSession, label: "Previous session needing attention"),
            Row(action: .nextAttentionSession, label: "Next session needing attention"),
            Row(action: .showAttention, label: "Show sessions needing attention"),
        ]),
        Group(title: "Workspaces", note: "A workspace groups sessions in the sidebar.", rows: [
            Row(action: .newWorkspace, label: "New workspace"),
            Row(action: .renameWorkspace, label: "Rename workspace"),
            Row(action: .deleteWorkspace, label: "Delete workspace"),
            Row(action: .focusWorkspace, label: "Mark workspace for focus"),
            Row(action: .toggleWorkspaceFilter, label: "Toggle the focus filter"),
            Row(action: .previousWorkspace, label: "Previous workspace"),
            Row(action: .nextWorkspace, label: "Next workspace"),
            Row(action: .toggleWorkspaceCollapse, label: "Collapse or expand workspace"),
        ]),
        Group(title: "Panes & splits", note: "Two shells side by side in one session.", rows: [
            Row(action: .toggleSplit, label: "Vertical split — show or hide"),
            Row(action: .toggleHorizontalSplit, label: "Horizontal split — show or hide"),
            Row(action: .focusLeftPane, label: "Focus the left or top pane"),
            Row(action: .focusRightPane, label: "Focus the right or bottom pane"),
            Row(action: .toggleScratch, label: "Scratch terminal"),
            Row(action: .toggleTerminalZoom, label: "Zoom the pane to full window"),
        ]),
        Group(title: "Windows", note: nil, rows: [
            Row(action: .newWindow, label: "New window"),
            Row(action: .renameWindow, label: "Rename window"),
            Row(action: .deleteWindow, label: "Delete window"),
        ]),
        Group(title: "View", note: nil, rows: [
            Row(action: .toggleSidebar, label: "Toggle the sidebar"),
            Row(action: .toggleFlaggedView, label: "Show flagged or all sessions"),
            Row(action: .toggleFlag, label: "Flag or unflag the session"),
            Row(action: .dashboard, label: "Dashboard"),
            Row(action: .toggleFullscreen, label: "Full screen"),
            Row(action: .selectTheme, label: "Select theme…"),
            Row(action: .toggleSearch, label: "Find in the terminal"),
        ]),
        Group(title: "Palettes", note: "Fuzzy-search everything; the palette lists what a key would do.", rows: [
            Row(action: .sessionPalette, label: "Go to session"),
            Row(action: .commandPalette, label: "Command palette"),
            Row(action: .customCommandPalette, label: "Custom commands"),
            Row(action: .keyboardShortcuts, label: "Keyboard shortcuts (this sheet)"),
        ]),
        Group(title: "Quick terminal", note: "A drop-down terminal over whatever app is in front.", rows: [
            Row(action: .quickTerminal, label: "Quick terminal (inside agx)"),
        ]),
        Group(title: "Font size", note: nil, rows: [
            Row(action: .increaseFontSize, label: "Bigger"),
            Row(action: .decreaseFontSize, label: "Smaller"),
            Row(action: .resetFontSize, label: "Actual size"),
        ]),
    ]

    /// Every built-in the sheet lists, in row order. `ShortcutsSheetTests` pins this equal to
    /// `BuiltinAction.allCases`, so a new action fails a test until it is grouped rather than dropping off.
    static let coveredActions: [BuiltinAction] = groups.flatMap { $0.rows.map(\.action) }

    /// The sheet as markdown, resolved against `keymap`. The reader renders it with `html: true`, so the
    /// `<kbd>` capsules pass through.
    public static func markdown(keymap: Keymap) -> String {
        var out = "# Keyboard shortcuts\n\n"
        out += "Every key here is rebindable in `~/.config/agterm/keymap.conf`; "
        out += "this sheet always shows what is bound right now. "
        out += "An action with no key is still one search away in the command palette.\n"

        for group in groups {
            out += "\n## \(group.title)\n"
            if let note = group.note { out += "\n\(note)\n" }
            out += "\n| Action | Keys |\n| --- | --- |\n"
            for row in group.rows {
                out += "| \(escape(row.label)) | \(keys(for: row.action, keymap: keymap)) |\n"
            }
            if group.title == "Quick terminal", let hotkey = keymap.globalHotkey {
                out += "| Summon quick terminal (system-wide) | \(kbd(hotkey)) |\n"
            }
        }

        let commands = keymap.commands
        if !commands.isEmpty {
            out += "\n## Your custom commands\n"
            out += "\nDefined by `command` lines in your `keymap.conf`.\n"
            out += "\n| Command | Keys |\n| --- | --- |\n"
            for command in commands {
                out += "| \(escape(command.name)) | \(customKeys(command.shortcut)) |\n"
            }
        }
        return out
    }

    /// The whole binding set for a built-in as kbd capsules: the menu chord first, then each monitor-bound
    /// alternative, joined with a thin ` · `; the palette-only italic when nothing is bound.
    private static func keys(for action: BuiltinAction, keymap: Keymap) -> String {
        var parts: [String] = []
        if let chord = keymap.equivalent(for: action) { parts.append(kbd([chord])) }
        parts.append(contentsOf: keymap.sequences(for: action).map(kbd))
        return parts.isEmpty ? "*palette only*" : parts.joined(separator: " · ")
    }

    /// A custom command's `shortcut` field (raw kitty `|`-separated alternatives) as kbd capsules, falling
    /// back to the raw text for anything the parser cannot read, and the palette-only italic when empty.
    private static func customKeys(_ shortcut: String) -> String {
        if shortcut.isEmpty { return "*palette only*" }
        guard let keybinds = parseKeybinds(shortcut) else { return "`\(escape(shortcut))`" }
        return keybinds.map(kbd).joined(separator: " · ")
    }

    /// One keybind (a chord, or a leader sequence) as kbd capsules; sequence chords are joined by a ` › `
    /// so a run of them cannot read as one chord.
    private static func kbd(_ keybind: Keybind) -> String {
        keybind.map { chord in chord.kbdGlyphs.map { "<kbd>\(escape($0))</kbd>" }.joined() }
            .joined(separator: " › ")
    }

    private static func kbd(_ chord: Chord) -> String { kbd([chord]) }

    /// Escapes the four characters that would otherwise be read as markup in a table cell.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "|", with: "&#124;")
    }
}
