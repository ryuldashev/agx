import AppKit
import Foundation

/// Bridges the macOS display-wake notification into agterm's app-local notification center, the way
/// `SystemAccessibilityObserver` bridges accessibility changes: AppKit posts it on
/// `NSWorkspace.notificationCenter`, not the default center surfaces observe.
///
/// Why any of this exists: `ghostty_surface_new` returns NULL for the whole time the display is asleep
/// (measured: 21 consecutive failures over 40s), so a session created by a scheduled job in that window
/// realizes no surface and its `--command` never runs. Nothing retries, because SwiftUI runs no layout for
/// an off-display window — `updateNSView` never fires — so the pane stays dead long after the machine is
/// usable again (#416). Creation starts succeeding the instant the displays wake, with the screen still
/// LOCKED, so wake is the earliest correct moment to re-attempt and no unlock hook is needed.
@MainActor
final class SystemWakeObserver {
    // written once on the main actor by `start()` and read again only from `deinit`, where nothing else holds
    // this object — see the note on that deinit for why it is not an `isolated deinit`.
    private nonisolated(unsafe) var wakeObserver: NSObjectProtocol?

    /// Register once for the process — the scene `.task` runs for every window, so this must be idempotent
    /// like `SystemAccessibilityObserver.start()`.
    func start() {
        guard wakeObserver == nil else { return }
        let workspace = NSWorkspace.shared
        wakeObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // NotificationCenter's callback is @Sendable even on a main queue; hop explicitly to stay correct
            // under Swift 6 isolation, matching SystemAccessibilityObserver's convention.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .agtermScreensDidWake, object: nil)
            }
        }
    }

    /// NOT an `isolated deinit`: back-deployed, that lowers to
    /// `swift_task_deinitOnExecutorMainActorBackDeploy`, which aborts the process on free
    /// (`pointer being freed was not allocated`, in `TaskLocal::StopLookupScope::~StopLookupScope`) — it
    /// took out every hosted test that let one of these objects go. `removeObserver` is thread-safe and
    /// needs no hop, so this deinit never needed the executor in the first place.
    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
