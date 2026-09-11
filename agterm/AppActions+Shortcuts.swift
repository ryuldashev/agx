import AppKit
import agtermCore
import Foundation

/// The Keyboard Shortcuts sheet: `ShortcutsSheet` renders the live keymap to markdown and the reader pane
/// shows it, so the sheet is generated, not shipped static — a `keymap.conf` rebind moves it.
extension AppActions {
    /// Renders the live keymap to `<stateDir>/keyboard-shortcuts.md` and opens it in the active session's
    /// reader pane. Regenerated on every invocation, so a `keymap.conf` edit is reflected on the next ⌘/.
    /// No-op without an active session (`PaletteCommand.keyboardShortcuts` gates on one) — the reader hosts
    /// in the session's split pane.
    func showKeyboardShortcuts() {
        guard let store, let id = store.selectedSessionID, let settingsModel else { return }
        let markdown = ShortcutsSheet.markdown(keymap: settingsModel.keymap)
        let url = Self.shortcutsStateDirectory.appendingPathComponent("keyboard-shortcuts.md")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
            return
        }
        store.openReader(id, spec: ReaderSpec(path: url.path))
    }

    /// The app's state directory, resolved as `agtermApp.init` does: the `AGTERM_STATE_DIR` override for
    /// test isolation, else the persistence default.
    private static var shortcutsStateDirectory: URL {
        ProcessInfo.processInfo.environment["AGTERM_STATE_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? PersistenceStore.defaultDirectory
    }
}
