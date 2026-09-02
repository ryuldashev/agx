import AppKit
import agtermCore

/// The permission wall (`PermissionPrimer`) as an AppKit alert: an explanation of WHY a macOS dialog says
/// "agx", a checkbox per area the app can ask for on the spot, and a way to see which pane is asking right
/// now. Shown once on a first launch and from Help ▸ Permissions afterwards.
@MainActor
enum PermissionsAlert {
    private static var presented = false

    /// Keeps the "Open Settings" row buttons' targets alive for the modal's lifetime — an NSButton does not
    /// retain its target, and these are created per presentation.
    private static var openSettingsTargets: [OpenSettingsTarget] = []

    /// Suppressed under XCUITest for `WelcomeAlert`'s reason: every test launches on a fresh state
    /// directory, so a first-run modal would open before the first assertion.
    static var isSuppressedForUITest: Bool {
        ContentView.isUITestLaunch && ProcessInfo.processInfo.environment["AGTERM_UITEST_SHOW_PERMISSIONS"] == nil
    }

    /// First-launch presentation, once per process. Marks itself shown BEFORE the modal, so a refused or
    /// half-finished pass cannot bring the wall back on the next launch — Help ▸ Permissions is the way
    /// back, and it is in the same menu as the other extras.
    static func presentOnce(settingsModel: SettingsModel, library: WindowLibrary) {
        guard !presented, !isSuppressedForUITest else { return }
        presented = true
        settingsModel.setPermissionsPrimerShown(true)
        // hop out of the caller's Task before the nested modal loop, as WelcomeAlert does: started from
        // inside the scene's `.task`, `runModal()` returns `.abort` immediately and nothing is drawn.
        DispatchQueue.main.async { present(library: library) }
    }

    /// The wall. Loops rather than recurses so "What's running now…" can return to it any number of times
    /// without stacking modal sessions.
    static func present(library: WindowLibrary) {
        while true {
            let built = makeAlert()
            let response = built.alert.runModal()
            openSettingsTargets.removeAll()
            switch response {
            case .alertSecondButtonReturn:
                presentRunning(library: library)
                continue
            case .alertFirstButtonReturn:
                let picked = zip(PermissionPrimer.probeableAreas, built.checkboxes)
                    .filter { $0.1.state == .on }.map(\.0)
                guard !picked.isEmpty else { return }
                Task { @MainActor in
                    let statuses = await PermissionProbe.request(picked)
                    summarize(picked, statuses: statuses)
                }
                return
            default:
                return
            }
        }
    }

    /// The alert and its checkboxes, in `PermissionPrimer.probeableAreas` order. Split out of `present()`
    /// so a hosted test can check the layout without running a modal.
    static func makeAlert() -> (alert: NSAlert, checkboxes: [NSButton]) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        var checkboxes: [NSButton] = []
        for area in PermissionPrimer.areas {
            if area.probePath != nil {
                let box = NSButton(checkboxWithTitle: area.title, target: nil, action: nil)
                box.state = .on
                box.setAccessibilityIdentifier("permission-\(area.id)-checkbox")
                checkboxes.append(box)
                stack.addArrangedSubview(row(control: box, reason: area.reason))
            } else if let anchor = area.settingsAnchor {
                let target = OpenSettingsTarget(anchor: anchor)
                openSettingsTargets.append(target)
                let button = NSButton(title: "\(area.title) — open Settings", target: target,
                                      action: #selector(OpenSettingsTarget.open))
                button.bezelStyle = .rounded
                button.setAccessibilityIdentifier("permission-\(area.id)-settings")
                stack.addArrangedSubview(row(control: button, reason: area.reason))
            }
        }
        stack.addArrangedSubview(label(PermissionPrimer.footnote, secondary: true))
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        let container = NSView(frame: stack.frame)
        container.addSubview(stack)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = PermissionPrimer.title
        alert.informativeText = PermissionPrimer.message
        alert.accessoryView = container
        alert.addButton(withTitle: "Grant")
        alert.addButton(withTitle: PermissionPrimer.runningButton)
        alert.addButton(withTitle: "Later")
        alert.buttons.first?.setAccessibilityIdentifier("permissions-grant")
        alert.buttons.last?.setAccessibilityIdentifier("permissions-later")
        alert.layout()
        if let reference = checkboxes.first {
            AlertAccessoryLayout.indent(stack, container: container, reference: reference, in: alert)
        }
        return (alert, checkboxes)
    }

    /// What every pane is running right now — the answer to "who asked?" for a dialog already on screen,
    /// since the dialog freezes the process that tripped it and it is still on this list while it waits.
    static func presentRunning(library: WindowLibrary) {
        let lines = runningLines(library: library)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = PermissionPrimer.runningTitle
        alert.informativeText = lines.isEmpty
            ? PermissionPrimer.runningEmpty
            : PermissionPrimer.runningMessage + "\n\n" + lines.joined(separator: "\n")
        alert.addButton(withTitle: "Back")
        alert.runModal()
    }

    /// One line per pane running something, durable panes read through their abduco program as `tree` does —
    /// a durable session's surface is the abduco client, so its argv would name abduco, not the agent.
    static func runningLines(library: WindowLibrary) -> [String] {
        let shellBasename = ProcessInfo.processInfo.environment["SHELL"].map(CommandRestore.basename)
        var lines: [String] = []
        for windowID in library.openIDs() {
            guard let store = library.store(for: windowID) else { continue }
            for workspace in store.workspaces {
                for session in workspace.sessions {
                    let main: [String]? = session.durable
                        ? DurableSpawn.foreground(session: session, stateDirectory: library.directory.path,
                                                  shellBasename: shellBasename)
                        : (session.surface as? GhosttySurfaceView).flatMap {
                            ForegroundProcess.running(for: $0, shellBasename: shellBasename)
                        }
                    let split = (session.splitSurface as? GhosttySurfaceView).flatMap {
                        ForegroundProcess.running(for: $0, shellBasename: shellBasename)
                    }
                    for argv in [main, split].compactMap({ $0 }) {
                        lines.append(PermissionPrimer.runningLine(workspace: workspace.name,
                                                                  session: session.displayName, argv: argv))
                    }
                }
            }
        }
        return lines
    }

    /// The result of a pass. A refusal cannot be retried from here — macOS records it and stops asking — so
    /// the summary offers System Settings whenever one came back denied.
    private static func summarize(_ areas: [PermissionPrimer.Area],
                                  statuses: [String: PermissionPrimer.Status]) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Permissions"
        alert.informativeText = areas
            .map { PermissionPrimer.summaryLine(area: $0, status: statuses[$0.id] ?? .unknown) }
            .joined(separator: "\n")
        alert.addButton(withTitle: "Done")
        if areas.contains(where: { statuses[$0.id] == .denied }) {
            alert.addButton(withTitle: "Open Privacy Settings")
        }
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: PermissionPrimer.privacySettingsAnchor) {
            NSWorkspace.shared.open(url)
        }
    }

    /// A control with its explanation underneath, indented to the control's text.
    private static func row(control: NSView, reason: String) -> NSView {
        let stack = NSStackView(views: [control, label(reason, secondary: true)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        return stack
    }

    private static func label(_ text: String, secondary: Bool) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        if secondary { field.textColor = .secondaryLabelColor }
        field.preferredMaxLayoutWidth = 460
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

/// Target for a row that can only be finished in System Settings; retained by `PermissionsAlert` for the
/// modal's lifetime.
@MainActor
private final class OpenSettingsTarget: NSObject {
    private let anchor: String

    init(anchor: String) { self.anchor = anchor }

    @objc func open() {
        guard let url = URL(string: anchor) else { return }
        NSWorkspace.shared.open(url)
    }
}
