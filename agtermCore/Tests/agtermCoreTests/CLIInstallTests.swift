import Testing
@testable import agtermCore

struct CLIInstallTests {
    private let ctl = CLIInstall.Link(source: "/Apps/agx.app/Contents/MacOS/agtermctl", name: "agtermctl")
    private let agx = CLIInstall.Link(source: "/Apps/agx.app/Contents/Resources/agx", name: "agx")

    @Test func installPathIsToolUnderInstallDir() {
        #expect(CLIInstall.installPath == "/usr/local/bin/agtermctl")
        #expect(CLIInstall.installPath(for: "agx") == "/usr/local/bin/agx")
        #expect(agx.installPath == "/usr/local/bin/agx")
    }

    @Test func shellQuoteWrapsPlainValue() {
        #expect(CLIInstall.shellQuote("/Applications/agterm.app") == "'/Applications/agterm.app'")
    }

    @Test func shellQuoteEscapesSingleQuotes() {
        #expect(CLIInstall.shellQuote("a'b") == "'a'\\''b'")
    }

    @Test func privilegedCommandLinksSourceToInstallPath() {
        let cmd = CLIInstall.privilegedInstallCommand(links: [ctl])
        #expect(cmd == "mkdir -p '/usr/local/bin' && ln -sf '/Apps/agx.app/Contents/MacOS/agtermctl' '/usr/local/bin/agtermctl'")
    }

    @Test func privilegedCommandLinksEveryToolInOneCommand() {
        let cmd = CLIInstall.privilegedInstallCommand(links: [ctl, agx])
        #expect(cmd == "mkdir -p '/usr/local/bin'"
            + " && ln -sf '/Apps/agx.app/Contents/MacOS/agtermctl' '/usr/local/bin/agtermctl'"
            + " && ln -sf '/Apps/agx.app/Contents/Resources/agx' '/usr/local/bin/agx'")
    }

    @Test func privilegedCommandQuotesSourceWithSpaces() {
        let link = CLIInstall.Link(source: "/My Apps/agx.app/Contents/MacOS/agtermctl", name: "agtermctl")
        let cmd = CLIInstall.privilegedInstallCommand(links: [link])
        #expect(cmd.contains("ln -sf '/My Apps/agx.app/Contents/MacOS/agtermctl' '/usr/local/bin/agtermctl'"))
    }

    @Test func describeJoinsNamesForTheAlert() {
        #expect(CLIInstall.describe([ctl]) == "agtermctl")
        #expect(CLIInstall.describe([ctl, agx]) == "agtermctl and agx")
        #expect(CLIInstall.describe([]) == "")
    }
}
