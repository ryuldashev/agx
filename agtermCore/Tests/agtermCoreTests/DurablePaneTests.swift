import Foundation
import Testing
@testable import agtermCore

struct DurablePaneTests {
    let id = UUID(uuidString: "9FF21911-7F9D-4B6C-AB63-020823B69671")!

    @Test func socketLivesUnderTheStateDirectory() {
        let socket = DurablePane.socketPath(stateDirectory: "/Users/rus/Library/Application Support/agx", sessionID: id)
        #expect(socket == "/Users/rus/Library/Application Support/agx/abduco/9FF21911-7F9D-4B6C-AB63-020823B69671")
        #expect(DurablePane.fits(socket: socket))
        #expect(DurablePane.pidFilePath(socket: socket) == socket + ".pid")
    }

    @Test func rejectsASocketPastTheSunPathCap() {
        let long = DurablePane.socketPath(stateDirectory: String(repeating: "x", count: 70), sessionID: id)
        #expect(!DurablePane.fits(socket: long))
    }

    @Test func programLineTakesTheExecCommandThenTheTypedOverride() {
        #expect(DurablePane.programLine(.init(command: "claude", initialInput: nil)) == "claude")
        #expect(DurablePane.programLine(.init(command: nil, initialInput: "zsh -lc 'exec claude --resume x'\n"))
                == "zsh -lc 'exec claude --resume x'")
        #expect(DurablePane.programLine(.init(command: nil, initialInput: nil)) == nil)
        #expect(DurablePane.programLine(.init(command: "", initialInput: "\n")) == nil)
        // a live server outranks the restore toggle: attach, with a login shell as the fallback.
        #expect(DurablePane.programLine(.init(command: nil, initialInput: nil), serverExists: true) == "/bin/zsh -l")
        #expect(DurablePane.programLine(.init(command: "claude", initialInput: nil), serverExists: true) == "claude")
    }

    @Test func wrapsOnSettingRequestOrExistingServerButNeverAPlainShell() {
        #expect(DurablePane.shouldWrap(settingOn: true, requested: false, serverExists: false, line: "claude"))
        #expect(DurablePane.shouldWrap(settingOn: false, requested: true, serverExists: false, line: "claude"))
        #expect(DurablePane.shouldWrap(settingOn: false, requested: false, serverExists: true, line: "claude"))
        #expect(!DurablePane.shouldWrap(settingOn: false, requested: false, serverExists: false, line: "claude"))
        #expect(!DurablePane.shouldWrap(settingOn: true, requested: true, serverExists: true, line: nil))
    }

    @Test func commandAttachesOrCreatesAndRecordsTheProgramPid() {
        let command = DurablePane.command(abduco: "/Applications/agx.app/Contents/Resources/abduco/abduco",
                                          socket: "/tmp/agx/abduco/ID",
                                          line: "zsh -lc 'exec claude --resume x --fork-session'")
        #expect(command == "'/Applications/agx.app/Contents/Resources/abduco/abduco' -A -f '/tmp/agx/abduco/ID' "
                + "/bin/zsh -lc 'printf %d $$ >'\\''/tmp/agx/abduco/ID.pid'\\''; "
                + "exec zsh -lc '\\''exec claude --resume x --fork-session'\\'''")
    }
}
