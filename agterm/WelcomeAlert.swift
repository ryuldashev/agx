import AppKit
import agtermCore

/// The first-launch alert pointing at the Help menu extras, with buttons for the two a Homebrew install
/// does not provide. Host-free copy and the due-decision are `agtermCore.FirstRunWelcome`.
@MainActor
enum WelcomeAlert {
    private static var presented = false

    /// Suppressed under XCUITest, since every test launches on a fresh isolated state directory and would
    /// otherwise open a modal before its first assertion. `WelcomeUITests` opts back in.
    static var isSuppressedForUITest: Bool {
        ContentView.isUITestLaunch && ProcessInfo.processInfo.environment["AGTERM_UITEST_SHOW_WELCOME"] == nil
    }

    /// Show the welcome once per process, marking it shown before any installer runs so a cancelled or
    /// failed install cannot bring it back on the next launch. `then` runs after the modal and its
    /// installers are done — the permission wall chains off it, and two modals opened side by side would
    /// stack, since a nested modal loop drains the main queue.
    static func presentOnce(settingsModel: SettingsModel, then: (() -> Void)? = nil) {
        guard !presented, !isSuppressedForUITest else { then?(); return }
        presented = true
        settingsModel.setWelcomeShown(true)
        // hop out of the caller's Task before the nested modal loop: started from inside the scene's
        // `.task`, `runModal()` returns `.abort` immediately and nothing is ever drawn.
        DispatchQueue.main.async {
            present()
            then?()
        }
    }

    private static func present() {
        let built = makeAlert()
        guard built.alert.runModal() == .alertFirstButtonReturn else { return }
        // each installer runs its own result alert, so they queue behind one another
        if built.skill.state == .on { SkillInstaller.run() }
        if built.hooks.state == .on { AgentHooksInstaller.run() }
    }

    /// The alert and its two option checkboxes, laid out and aligned. Split out of `present()` so a hosted
    /// test can check the layout without running a modal.
    static func makeAlert() -> (alert: NSAlert, skill: NSButton, hooks: NSButton) {
        let skill = checkbox(title: FirstRunWelcome.skillOption, identifier: "welcome-skill-checkbox")
        let hooks = checkbox(title: FirstRunWelcome.hooksOption, identifier: "welcome-hooks-checkbox")
        let stack = NSStackView(views: [skill, hooks])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        let container = NSView(frame: stack.frame)
        container.addSubview(stack)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = FirstRunWelcome.title
        alert.informativeText = FirstRunWelcome.message
        alert.accessoryView = container
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Later")
        alert.buttons.first?.setAccessibilityIdentifier("welcome-install")
        alert.buttons.last?.setAccessibilityIdentifier("welcome-later")
        alert.layout()
        AlertAccessoryLayout.indent(stack, container: container, reference: skill, in: alert)
        return (alert, skill, hooks)
    }

    private static func checkbox(title: String, identifier: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = .on
        button.setAccessibilityIdentifier(identifier)
        return button
    }
}
