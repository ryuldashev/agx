import Foundation

/// Whether this launch is the first: the due-decision behind the Welcome panel (`WelcomeWindow` app-side).
public enum FirstRunWelcome {
    /// Files a previous launch leaves behind. The control socket is excluded: it is bound before the scene
    /// task runs, so its presence says nothing about earlier launches.
    static let priorStateNames = ["settings.json", "workspaces.json", "windows"]

    /// Whether any prior-launch state exists in `directory`. Must be read before the app writes anything,
    /// since the first launch seeds a session and saves its window within a second of the scene appearing.
    public static func hasPriorState(in directory: URL) -> Bool {
        priorStateNames.contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Whether to show the welcome: never twice, and never to a user who has run agterm before. The two
    /// terms answer different questions, so both are needed. `welcomeShown` covers a state directory that
    /// carries the flag, and `hasPriorState` covers everyone who upgraded into this feature, whose settings
    /// predate the flag and would otherwise read as a fresh install.
    public static func isDue(welcomeShown: Bool?, hasPriorState: Bool) -> Bool {
        welcomeShown != true && !hasPriorState
    }
}
