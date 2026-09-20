import Foundation
import Testing
@testable import agtermCore

struct ShortcutsSheetTests {
    private var defaultKeymap: Keymap { Keymap(builtinOverrides: [:], commands: []) }

    @Test func everyBuiltinAppearsExactlyOnce() {
        #expect(Set(ShortcutsSheet.coveredActions) == Set(BuiltinAction.allCases))
        #expect(ShortcutsSheet.coveredActions.count == BuiltinAction.allCases.count)
    }

    @Test func shippedChordRendersAsKbdCapsules() {
        let md = ShortcutsSheet.markdown(keymap: defaultKeymap)
        #expect(md.contains("| Action | Keys |"))
        #expect(md.contains("<kbd>⌘</kbd><kbd>N</kbd>"))
        #expect(md.contains("<kbd>⇧</kbd><kbd>⌘</kbd><kbd>G</kbd>"))
    }

    @Test func keylessActionSaysPaletteOnly() {
        let md = ShortcutsSheet.markdown(keymap: defaultKeymap)
        // Rename session ships no chord; its row must read palette-only rather than an empty cell.
        let line = md.split(separator: "\n").first { $0.contains("Rename session") }
        #expect(line?.contains("*palette only*") == true)
    }

    @Test func aRebindMovesTheSheet() {
        let rebound = Keymap(builtinOverrides: [.newSession: Chord(mods: [.command, .shift], key: "k")],
                             commands: [])
        let md = ShortcutsSheet.markdown(keymap: rebound)
        let line = md.split(separator: "\n").first { $0.contains("New session |") }
        #expect(line?.contains("<kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd>") == true)
        #expect(line?.contains("<kbd>⌘</kbd><kbd>N</kbd>") == false)
    }

    @Test func customCommandsGetTheirOwnSection() {
        let keymap = Keymap(
            builtinOverrides: [:],
            commands: [
                CustomCommand(name: "Deploy", command: "make deploy", shortcut: "cmd+shift+y"),
                CustomCommand(name: "Notes", command: "echo hi", shortcut: ""),
            ])
        let md = ShortcutsSheet.markdown(keymap: keymap)
        #expect(md.contains("## Your custom commands"))
        let deploy = md.split(separator: "\n").first { $0.contains("Deploy") }
        #expect(deploy?.contains("<kbd>⇧</kbd><kbd>⌘</kbd><kbd>Y</kbd>") == true)
        let notes = md.split(separator: "\n").first { $0.contains("Notes") }
        #expect(notes?.contains("*palette only*") == true)
    }

    @Test func globalHotkeyGetsARowUnderQuickTerminal() {
        let keymap = Keymap(builtinOverrides: [:], commands: [],
                            globalHotkey: Chord(mods: [.control, .option], key: "space"))
        let md = ShortcutsSheet.markdown(keymap: keymap)
        let line = md.split(separator: "\n").first { $0.contains("system-wide") }
        #expect(line?.contains("<kbd>⌃</kbd><kbd>⌥</kbd><kbd>␣</kbd>") == true)
    }

    @Test func aLeaderSequenceAlternativeRendersBothChords() {
        let keymap = Keymap(builtinOverrides: [:], commands: [],
                            builtinSequences: [.dashboard: [[Chord(mods: [.control], key: "a"),
                                                             Chord(mods: [], key: "d")]]])
        let md = ShortcutsSheet.markdown(keymap: keymap)
        let line = md.split(separator: "\n").first { $0.contains("Dashboard |") }
        #expect(line?.contains("<kbd>⌃</kbd><kbd>A</kbd> › <kbd>D</kbd>") == true)
    }
}
