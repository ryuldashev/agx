import AppKit
import agtermCore
import SwiftUI

/// The Welcome panel's state: the setup checklist read from the system, the discovery map read from the
/// tracker. Re-read every two seconds while the panel is open, since the things it reports change
/// elsewhere — System Settings, an installer's result window, an agent in a pane.
@MainActor
final class WelcomeModel: ObservableObject {
    @Published private(set) var states: [OnboardingSetup.Step: OnboardingSetup.State] = [:]
    @Published private(set) var discovered: Set<Discovery> = []

    let settingsModel: SettingsModel
    let library: WindowLibrary
    let tracker: DiscoveryTracker
    private var timer: Timer?

    init(settingsModel: SettingsModel, library: WindowLibrary, tracker: DiscoveryTracker) {
        self.settingsModel = settingsModel
        self.library = library
        self.tracker = tracker
    }

    var setupComplete: Bool { OnboardingSetup.isComplete(states) }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        discovered = Set(tracker.discovered.keys)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let next = await OnboardingProbe.read(settings: settingsModel.settings)
            if next != states { states = next }
        }
    }

    func perform(_ step: OnboardingSetup.Step) {
        switch step {
        case .notifications:
            Task { await OnboardingProbe.requestNotifications(); refresh() }
        case .toolPermissions:
            settingsModel.setPermissionsPrimerShown(true)
            PermissionsAlert.present(library: library)
        case .cli:
            CLIInstaller.run()
        case .hooks:
            AgentHooksInstaller.run()
        case .skill:
            SkillInstaller.run()
        case .agent:
            NotificationCenter.default.post(name: SettingsView.openAgentsTab, object: nil)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        refresh()
    }

    func resetDiscoveries() {
        tracker.reset()
        refresh()
    }

    /// The guide lives in the repository until it ships in the bundle; a chapter link is relative to it.
    static func guideURL(_ chapter: String? = nil) -> URL? {
        URL(string: Brand.homepage + "/blob/master/docs/guide/" + (chapter ?? "README.md"))
    }
}

/// One non-modal window, reused: Help ▸ Getting Started… and the first launch both land here.
@MainActor
enum WelcomeWindow {
    private static var window: NSWindow?
    private static var model: WelcomeModel?

    /// Suppressed under XCUITest like the alert it replaced; `WelcomeUITests` opts back in.
    static var isSuppressedForUITest: Bool {
        ContentView.isUITestLaunch && ProcessInfo.processInfo.environment["AGTERM_UITEST_SHOW_WELCOME"] == nil
    }

    /// The first-launch opening: marks the welcome AND the permission wall as shown, since the wall's rows
    /// are now the checklist's Permissions row and two dialogs at launch would stack.
    static func presentOnFirstLaunch(settingsModel: SettingsModel, library: WindowLibrary, tracker: DiscoveryTracker) {
        guard !isSuppressedForUITest else { return }
        settingsModel.setWelcomeShown(true)
        settingsModel.setPermissionsPrimerShown(true)
        present(settingsModel: settingsModel, library: library, tracker: tracker)
    }

    static func present(settingsModel: SettingsModel, library: WindowLibrary, tracker: DiscoveryTracker) {
        if let window, let model {
            model.start()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = WelcomeModel(settingsModel: settingsModel, library: library, tracker: tracker)
        let view = WelcomeView(model: model, onClose: { close() })
        // taller than a small laptop's screen, so it scrolls past the usable height; a ScrollView has no
        // fitting height of its own, hence the content is measured first and the frame set explicitly.
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 60
        let height = min(NSHostingView(rootView: view).fittingSize.height, maxHeight)
        let root = ScrollView { view }.frame(width: WelcomeView.width, height: height)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Welcome to \(Brand.productName)"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setAccessibilityIdentifier("welcome-window")
        window.center()
        // the red close button bypasses `close()`; the timer must stop with the window either way.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { forget() }
        }
        self.window = window
        self.model = model
        model.start()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        let closing = window
        forget()
        closing?.close()
    }

    private static func forget() {
        model?.stop()
        window = nil
        model = nil
    }
}
