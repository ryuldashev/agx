import AppKit
import ApplicationServices
import agtermCore
import UserNotifications

/// Reads the real state behind each Welcome checklist row — TCC, symlinks, hook files, settings — so a
/// row says "done" because the thing is there, not because a dialog was once dismissed. Every read is
/// silent: nothing here raises a macOS prompt (the folder areas that would are behind Review…).
@MainActor
enum OnboardingProbe {
    typealias State = OnboardingSetup.State

    static func read(settings: AppSettings) async -> [OnboardingSetup.Step: State] {
        var states: [OnboardingSetup.Step: State] = [:]
        states[.notifications] = await notifications()
        states[.toolPermissions] = toolPermissions()
        states[.cli] = cli()
        states[.hooks] = hooks()
        states[.skill] = skill()
        states[.agent] = agent(settings: settings)
        return states
    }

    static func notifications() async -> State {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .done("Banners and the Dock badge are allowed.")
        case .denied: return .pending("Turned off in System Settings ▸ Notifications ▸ agx.")
        case .notDetermined: return .pending(nil)
        @unknown default: return .pending(nil)
        }
    }

    /// The three areas with no dialog of their own. Optional: most people never need them, and a row that
    /// blocked "setup complete" on Screen Recording would push everyone to grant more than they use.
    static func toolPermissions() -> State {
        var granted: [String] = []
        if AXIsProcessTrusted() { granted.append("Accessibility") }
        if CGPreflightScreenCaptureAccess() { granted.append("Screen Recording") }
        if hasFullDiskAccess() { granted.append("Full Disk Access") }
        return .optional(granted.isEmpty ? "None granted — fine until a tool asks." : "Granted: " + granted.joined(separator: ", "))
    }

    /// FDA has no API; opening a file only FDA unlocks answers it without a prompt.
    private static func hasFullDiskAccess() -> Bool {
        let tcc = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = FileHandle(forReadingAtPath: tcc.path) else { return false }
        try? handle.close()
        return true
    }

    static func cli() -> State {
        let fm = FileManager.default
        let bundle = Bundle.main.bundlePath
        var missing: [String] = []
        var foreign: [String] = []
        for name in [CLIInstall.toolName, CLIInstall.agxName] {
            let path = CLIInstall.installPath(for: name)
            guard let target = try? fm.destinationOfSymbolicLink(atPath: path) else {
                if fm.fileExists(atPath: path) { foreign.append(name) } else { missing.append(name) }
                continue
            }
            if !OnboardingSetup.linkPointsIntoBundle(target, bundlePath: bundle) || !fm.fileExists(atPath: target) {
                foreign.append(name)
            }
        }
        if missing.isEmpty, foreign.isEmpty { return .done("agtermctl and agx are on your PATH.") }
        if !foreign.isEmpty {
            return .pending("\(foreign.joined(separator: " and ")) in \(CLIInstall.installDirectory) points at another build or tool; Install… relinks it here.")
        }
        return .pending(nil)
    }

    static func hooks() -> State {
        let status = AgentHooksInstaller.status()
        if status.eligible.isEmpty { return .pending("No agent with a config directory was found on this Mac yet.") }
        if status.installed.isEmpty { return .pending("Found: " + status.eligible.joined(separator: ", ") + ".") }
        let rest = status.eligible.filter { !status.installed.contains($0) }
        let detail = "Installed for " + status.installed.joined(separator: ", ")
            + (rest.isEmpty ? "." : "; not yet for " + rest.joined(separator: ", ") + ".")
        return .done(detail)
    }

    static func skill() -> State {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var installed: [String] = []
        var foreign: [String] = []
        for (agent, base) in [("Claude Code", ".claude"), ("Codex", ".codex")] where fm.fileExists(atPath: home + "/" + base) {
            let skill = SkillInstall.skillDirectory(home: home, base: base) + "/SKILL.md"
            guard let contents = try? String(contentsOfFile: skill, encoding: .utf8) else { continue }
            if contents.contains(SkillInstall.marker) { installed.append(agent) } else { foreign.append(agent) }
        }
        if !installed.isEmpty { return .done("Installed for " + installed.joined(separator: ", ") + ".") }
        if !foreign.isEmpty { return .pending("A different '\(SkillInstall.skillName)' skill is already there for " + foreign.joined(separator: ", ") + ".") }
        return .pending(nil)
    }

    static func agent(settings: AppSettings) -> State {
        let connected = settings.agents ?? []
        if !connected.isEmpty { return .done("Connected: " + connected.map(\.name).joined(separator: ", ") + ".") }
        let found = AgentCatalog.detectInstalled()
        if found.isEmpty { return .pending("No agent CLI found on this Mac. Install one (claude, codex, gemini…) and come back.") }
        return .pending("Found on this Mac: " + found.map(\.name).joined(separator: ", ") + ".")
    }

    // MARK: - Actions

    /// Ask for notification permission when macOS has not decided yet; once refused, only System Settings
    /// can flip it, so that case opens the pane.
    static func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        if current.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
        } else {
            open("x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Brand.bundleID)")
        }
    }

    static func open(_ anchor: String) {
        if let url = URL(string: anchor) { NSWorkspace.shared.open(url) }
    }
}
