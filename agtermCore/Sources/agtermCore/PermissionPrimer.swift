import Foundation

/// The permission wall: what the programs running in panes ask macOS for, and why the dialog names agterm.
///
/// A pane's tools are agterm's CHILDREN, so TCC attributes every request they make to the app — "agx would
/// like to access Apple Music and your media library" is a `find ~` or `du -sh ~/*` walking into
/// `~/Music`, not the terminal wanting music. That costs the user twice: the dialog names the wrong asker,
/// and it arrives in the middle of unrelated work. The primer answers both by naming the areas up front and
/// granting them in one sitting, the way an app onboarding does.
///
/// Host-free by design: the catalog, the copy and the due-decision live here; raising an actual macOS
/// dialog needs a real filesystem read, which is app-side (`PermissionProbe`).
public enum PermissionPrimer {
    /// How a row is satisfied. macOS has no "request" API for the file-shaped services — the prompt is a
    /// side effect of touching the data — so a row is either something we can probe or something the user
    /// flips in System Settings.
    public enum Grant: Sendable, Equatable {
        /// Read `path` (home-relative) to raise the prompt. The path must be one a normal Mac HAS: a probe
        /// of something missing returns ENOENT without ever reaching TCC, so nothing is asked and nothing
        /// is recorded.
        case probe(path: String)
        /// No probe exists (the service guards an API, a device, or the whole disk) — open this System
        /// Settings pane instead.
        case settings(anchor: String)
    }

    /// One protected area, in the user's terms.
    public struct Area: Identifiable, Sendable, Equatable {
        public let id: String
        public let title: String
        /// What a pane's tools do to reach it. This is the sentence that turns "why is agx asking?" into an
        /// answer, so it names a CONCRETE command wherever one is typical.
        public let reason: String
        public let grant: Grant

        public init(id: String, title: String, reason: String, grant: Grant) {
            self.id = id
            self.title = title
            self.reason = reason
            self.grant = grant
        }

        /// The home-relative path this area is probed with, nil for a Settings-only row.
        public var probePath: String? {
            if case let .probe(path) = grant { return path }
            return nil
        }

        /// The `x-apple.systempreferences:` anchor for a Settings-only row, nil for a probeable one.
        public var settingsAnchor: String? {
            if case let .settings(anchor) = grant { return anchor }
            return nil
        }
    }

    /// The outcome of asking for one area, as the summary reports it.
    public enum Status: String, Sendable {
        /// The probe read the data: the grant exists and survives until the user revokes it.
        case granted
        /// The probe was refused — the user pressed Don't Allow, now or earlier. Only System Settings can
        /// undo that; macOS will not ask a second time.
        case denied
        /// Nothing to ask for: the area does not exist on this Mac (no Music library, no Photos library).
        case absent
        /// A Settings-only row, or a probe that failed for a reason that is not a permission (an unreadable
        /// mount, a race with a delete).
        case unknown
    }

    /// Privacy & Security root, for the summary's "review them all" button.
    public static let privacySettingsAnchor = "x-apple.systempreferences:com.apple.preference.security?Privacy"

    /// The wall, in the order it is shown. Probeable rows first — those are the ones the user can finish
    /// here and now, and the first three are what a plain home-directory sweep walks into, which is the
    /// single most common way this app ends up on screen asking for something odd.
    public static let areas: [Area] = [
        Area(id: "media",
             title: "Music and media library",
             reason: "A sweep of your home folder (find ~, du -sh ~/*, a backup script) walks into ~/Music.",
             grant: .probe(path: "Music/Music/Music Library.musiclibrary")),
        Area(id: "photos",
             title: "Photos library",
             reason: "The same sweep walks into ~/Pictures; osxphotos and image tools read it on purpose.",
             grant: .probe(path: "Pictures/Photos Library.photoslibrary")),
        Area(id: "desktop",
             title: "Desktop folder",
             reason: "Anything you run from or against ~/Desktop — a screenshot pipeline, a quick script.",
             grant: .probe(path: "Desktop")),
        Area(id: "documents",
             title: "Documents folder",
             reason: "Repos, notes and scratch files under ~/Documents; also where many installers write.",
             grant: .probe(path: "Documents")),
        Area(id: "downloads",
             title: "Downloads folder",
             reason: "curl and browser downloads land in ~/Downloads, and installers unpack from it.",
             grant: .probe(path: "Downloads")),
        Area(id: "fulldisk",
             title: "Full Disk Access",
             reason: "Only for tools that read protected system data (Mail, Messages, other apps' state). "
                 + "Grant it deliberately — it covers everything the boxes above do, and much more.",
             grant: .settings(anchor: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")),
        Area(id: "accessibility",
             title: "Accessibility",
             reason: "Scripts that drive other apps' windows or send synthetic keystrokes ask through agx.",
             grant: .settings(anchor: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")),
        Area(id: "screen",
             title: "Screen Recording",
             reason: "screencapture and any CLI that grabs a window or the screen ask through agx.",
             grant: .settings(anchor: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")),
    ]

    /// The rows the wall can finish on its own, pre-ticked when the primer opens.
    public static var probeableAreas: [Area] { areas.filter { $0.probePath != nil } }

    public static let title = "Permissions macOS asks agx for"

    public static let message = """
    Tools you run in a pane are agx's child processes, so macOS credits their requests to agx: a dialog \
    saying "agx would like to access…" is a command in one of your panes, not the terminal itself.

    Granting the areas you actually use now means the dialogs arrive here, in a row, instead of \
    interrupting work later. Nothing is granted until you press Grant, and each one still opens the real \
    macOS dialog, which you can refuse.
    """

    /// Shown under the checkboxes: the honest limits of the wall.
    public static let footnote =
        "Full Disk Access, Accessibility and Screen Recording have no dialog to raise — they open System Settings."

    /// The button that answers "who asked?" for a dialog already on screen.
    public static let runningButton = "What's running now…"

    public static let runningTitle = "Running in your panes right now"

    /// Header for the attribution list. A TCC dialog BLOCKS the process that tripped it, so whatever is on
    /// this list while a dialog waits is the asker — that is the whole trick, and it is worth saying.
    public static let runningMessage = """
    A permission dialog freezes the process that tripped it, so while one is on screen the command that \
    asked is still listed here.
    """

    public static let runningEmpty = "Every pane is sitting at its prompt — nothing is running to ask for anything."

    /// Whether to open the primer unprompted: once per install, flag-only.
    ///
    /// Deliberately NOT gated on `hasPriorState` the way `FirstRunWelcome.isDue` is. The welcome points at
    /// extras a returning user already knows about, so showing it on an upgrade would be noise; the wall is
    /// new to everyone, and the people who most need it are exactly the ones who have been answering these
    /// dialogs blind for months. It grants nothing on its own — every row still needs a tick and a press —
    /// so a single modal on the launch after an upgrade is a fair trade.
    public static func isDue(primerShown: Bool?) -> Bool {
        primerShown != true
    }

    /// The summary line for one finished row.
    public static func summaryLine(area: Area, status: Status) -> String {
        switch status {
        case .granted: return "\(area.title): granted"
        case .denied: return "\(area.title): refused — turn it on in System Settings if you need it"
        case .absent: return "\(area.title): nothing on this Mac to grant"
        case .unknown: return "\(area.title): unchanged"
        }
    }

    /// One line of the attribution list: where the command runs and what it is. Long argv is clipped, since
    /// this is an alert, not a log — the point is recognizing the command, not reading all of it.
    public static func runningLine(workspace: String, session: String, argv: [String]) -> String {
        let command = argv.joined(separator: " ")
        let clipped = command.count > 110 ? command.prefix(110) + "…" : command[...]
        return "\(workspace) ▸ \(session) — \(clipped)"
    }
}
