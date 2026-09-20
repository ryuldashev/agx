import AppKit
import Foundation
import OSLog
import Sparkle
import agtermCore

/// The app side of auto-update (ADR 0004): a Sparkle updater fed by the appcast attached to the latest
/// GitHub release, with the state it moves through mirrored into `AppUpdateState` for `tree`, `update.*`
/// and the events ring. Sparkle owns the check schedule, the download, the EdDSA + code-signature
/// verification, the swap and the relaunch; durable panes (ADR 0001) mean that relaunch reattaches every
/// agent instead of restarting it, which is what makes an update cheap enough to take mid-day.
@MainActor
@Observable
final class AppUpdater: NSObject {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "AppUpdater")

    /// Whether the updater runs at all — see `AppUpdatePolicy`. A disabled updater never touches the
    /// network, is absent from `tree`, and its menu item is greyed out.
    let enabled: Bool
    private(set) var state: AppUpdateState = .idle
    private(set) var available: String?
    private(set) var lastChecked: Date?
    private(set) var lastError: String?

    @ObservationIgnored private let library: WindowLibrary
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    static let runningVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

    init(library: WindowLibrary) {
        self.library = library
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        enabled = AppUpdatePolicy.isEnabled(version: Self.runningVersion, isDebugBuild: isDebugBuild,
                                            environment: ProcessInfo.processInfo.environment)
        super.init()
    }

    /// Idempotent; called from the scene task. Starting is what arms Sparkle's scheduled check, so a
    /// disabled updater is simply never started.
    func start() {
        guard enabled, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// Sparkle's own gate: false while a check or install is already in flight, so the menu item mirrors it.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    var node: ControlUpdateNode? {
        guard enabled else { return nil }
        return ControlUpdateNode(version: Self.runningVersion, state: state.rawValue, available: available,
                                 lastChecked: lastChecked.map { ControlScheduledNode.isoString($0) },
                                 automatic: controller?.updater.automaticallyChecksForUpdates ?? true,
                                 error: lastError)
    }

    /// `update.check`: ask the feed without UI. The outcome arrives through the delegate.
    func checkInBackground() -> ControlResponse {
        guard let controller else { return Self.disabledResponse }
        guard controller.updater.canCheckForUpdates else {
            return ControlResponse(ok: false, error: "an update check or install is already in progress")
        }
        state = .checking
        lastError = nil
        controller.updater.checkForUpdateInformation()
        return ControlResponse(ok: true, result: ControlResult(update: node))
    }

    /// `update.install` and the menu item: Sparkle's standard dialog — "Install and Relaunch", "Install on
    /// Quit", "Later". Runs a fresh check first, so it also answers "you're up to date" when nothing is new.
    func checkForUpdates() -> ControlResponse {
        guard let controller else { return Self.disabledResponse }
        guard controller.updater.canCheckForUpdates else {
            return ControlResponse(ok: false, error: "an update check or install is already in progress")
        }
        lastError = nil
        controller.checkForUpdates(nil)
        return ControlResponse(ok: true, result: ControlResult(update: node))
    }

    func status() -> ControlResponse {
        guard enabled else { return Self.disabledResponse }
        return ControlResponse(ok: true, result: ControlResult(update: node))
    }

    private static let disabledResponse = ControlResponse(
        ok: false, error: "updater disabled (local 0.0.0 or Debug build, isolated instance, or \(AppUpdatePolicy.optOutVariable)=1)")

    private func emit(_ kind: ControlEventKind, version: String) {
        library.recordControlEvent(ControlEventDraft(kind: kind, payload: ControlEventPayload(name: Brand.productName,
                                                                                               version: version)))
    }
}

extension AppUpdater: @preconcurrency SPUUpdaterDelegate {
    func feedURLString(for _: SPUUpdater) -> String? {
        AppUpdatePolicy.stagingFeed(environment: ProcessInfo.processInfo.environment)
    }

    func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        // a re-check that finds the same version again is not news to the events ring
        let isNew = available != version
        available = version
        state = .available
        if isNew { emit(.updateAvailable, version: version) }
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        available = nil
        state = .idle
    }

    func updater(_: SPUUpdater, willDownloadUpdate _: SUAppcastItem, with _: NSMutableURLRequest) {
        state = .downloading
    }

    func updater(_: SPUUpdater, didExtractUpdate _: SUAppcastItem) {
        state = .ready
    }

    func updater(_: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .installing
        emit(.updateInstalling, version: item.displayVersionString)
    }

    /// Sparkle terminates the app through the normal `NSApp.terminate` path, which would otherwise raise the
    /// quit-confirmation alert and stall the install behind it. Same flag `AppActions.restartApp` sets.
    func updaterWillRelaunchApplication(_: SPUUpdater) {
        AppDelegate.isRestarting = true
    }

    func updater(_: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate _: SUAppcastItem,
                 state _: SPUUserUpdateState) {
        // "Later" and "Skip" leave a known newer version behind; only an install keeps its state
        if choice != .install { state = .available }
    }

    func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: (any Error)?) {
        lastChecked = Date()
        guard let error else { return }
        let nsError = error as NSError
        // Sparkle reports "no update found" and a user's "Later" as errors of the cycle, not of the check
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == Int(SUError.noUpdateError.rawValue) || nsError.code == Int(SUError.installationCanceledError.rawValue) {
            return
        }
        // Sparkle's top-level text is "try again later"; the underlying error says what actually failed
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription
        lastError = underlying.map { "\(error.localizedDescription) (\($0))" } ?? error.localizedDescription
        state = .error
        Self.logger.error("update cycle failed: \(self.lastError ?? "", privacy: .public)")
    }
}
