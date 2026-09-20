import agtermCore
import AppKit
import SwiftUI

/// Holding ⌥ alone names the window chrome: one panel listing every visible control as icon + the short
/// token we use for it in conversation (`docs/ui-lexicon.md`) + its shortcut, so a button can be reported by
/// name instead of by screenshot.
///
/// A panel rather than a badge per button: the tokens are wider than the 14pt gap between the title-bar
/// icons, so floating labels overlapped each other and ran off the window edge. One list stays aligned at
/// any window width and reads as a cheat sheet.
@MainActor
@Observable
final class OptionHintTracker {
    static let shared = OptionHintTracker()

    private(set) var down = false

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    /// A held ⌥ cannot be screenshotted — the capture shortcut needs the same keyboard — so this pins the
    /// panel open for the whole run: `open --env AGX_HINTS_ALWAYS=1 ~/Applications/agx.app`.
    @ObservationIgnored private let pinned: Bool

    private init() {
        pinned = ProcessInfo.processInfo.environment["AGX_HINTS_ALWAYS"] == "1"
        down = pinned
        // .flagsChanged fires for every modifier, so publish only on a real change — otherwise each ⌘ press
        // re-renders the whole title bar.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // ⌥ ALONE: any combination is a shortcut being typed (⌘⌥N, ⌃⌥↑), and flashing the panel
            // mid-chord reads as a glitch.
            let next = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option
            if let self, !self.pinned, self.down != next {
                self.down = next
                if next { ActionJournal.shared.log("state", ["hints": "on"]) }
            }
            return event
        }
        // ⌥⇥ switches app without delivering the release here, so the panel would stay pinned over the chrome.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pinned, self.down else { return }
                self.down = false
            }
        }
    }
}

/// One row of the ⌥ panel: the control's own SF Symbol, the token we call it by, and its shortcut.
struct OptionHintItem: Identifiable {
    let token: String
    let symbol: String
    let shortcut: String?

    var id: String { token }

    init(_ token: String, _ symbol: String, _ shortcut: String?) {
        self.token = token
        self.symbol = symbol
        self.shortcut = shortcut
    }
}

/// The ⌥-hold cheat sheet, grouped by chrome surface. Never hit-testable, so it cannot swallow a click on
/// the chrome it is describing.
struct OptionHintsPanel: View {
    let titleBar: [OptionHintItem]
    let sidebar: [OptionHintItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("title bar", titleBar)
            if !sidebar.isEmpty { section("sidebar", sidebar) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [OptionHintItem]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.bottom, 1)
            // a Grid, so the icon / token / shortcut columns line up down the whole list.
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(items) { item in
                    GridRow {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11))
                            .frame(width: 16)
                            .gridColumnAlignment(.center)
                        Text(item.token)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text(item.shortcut ?? "—")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(item.shortcut == nil ? 0.3 : 0.6))
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .foregroundStyle(Color.white)
    }
}
