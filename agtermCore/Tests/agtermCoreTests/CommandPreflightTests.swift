import Foundation
import Testing
@testable import agtermCore

struct CommandPreflightTests {
    @Test func judgesBareAgentNames() {
        #expect(CommandPreflight.executableToken("claude") == "claude")
        #expect(CommandPreflight.executableToken("claude --resume abc --fork-session") == "claude")
        #expect(CommandPreflight.executableToken("  codex  ") == "codex")
    }

    @Test func declinesWhatItCannotCheck() {
        // shell lines: the first word is not the binary, so resolving it would be wrong
        #expect(CommandPreflight.executableToken("zsh -lc 'exec claude'") == nil)
        #expect(CommandPreflight.executableToken("FOO=1 claude") == nil)
        #expect(CommandPreflight.executableToken("a && b") == nil)
        #expect(CommandPreflight.executableToken("f | g") == nil)
        #expect(CommandPreflight.executableToken("echo $(date)") == nil)
        // explicit paths resolve themselves at spawn
        #expect(CommandPreflight.executableToken("/usr/bin/top") == nil)
        #expect(CommandPreflight.executableToken("./run.sh") == nil)
        #expect(CommandPreflight.executableToken("~/bin/agent") == nil)
        // nothing to judge
        #expect(CommandPreflight.executableToken("") == nil)
        #expect(CommandPreflight.executableToken("   ") == nil)
    }

    @Test func messageNamesCommandAndFix() {
        let message = CommandPreflight.unresolvedMessage(command: "claude --resume abc")
        #expect(message.contains("claude"))
        #expect(!message.contains("--resume"))   // the binary is the problem, not its flags
        #expect(message.contains("PATH"))
        #expect(message.contains("shell"))
    }
}
