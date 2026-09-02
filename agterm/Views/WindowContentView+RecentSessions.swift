import agtermCore
import AppKit
import SwiftUI

/// Title-bar "jump to a session" buttons, split out of `WindowContentView` to keep that file under the
/// 1000-line limit (the `+Dashboard`/`+Zoom` extension pattern): the recent-sessions popover — the mouse
/// equivalent of the Ctrl-Tab switcher — and the attention bell. Both open a session picker over the
/// frontmost window and are referenced from `WindowContentView.titlebarRow`.
extension WindowContentView {
    /// The frontmost window's most-recently-used sessions, EXCLUDING the current one (not a jump target —
    /// you're already there), scoped to the visible/filtered set and capped like the Ctrl-Tab switcher. The
    /// live refresh rides the OBSERVED `activeSession`/`navigableSessions` reads — every `sessionRecency`
    /// mutation co-occurs with one (a push on select changes `activeSession`, a prune on close changes
    /// `navigableSessions`); `sessionRecency` itself is `@ObservationIgnored` and registers no observation.
    private var recentSessions: [UUID] {
        store.navigableRecentSessions(limit: SessionSwitcher.maxCandidates)
    }

    /// The app-wide recently CLOSED sessions, newest first and capped like the MRU list. Workspaces are left
    /// to File ▸ Open Recent: this popover is the session switcher, and a workspace row here would restore a
    /// whole tree from a control that otherwise only moves the selection.
    /// A `.session` entry whose payload is nil is dropped: it draws a row whose click resolves to nothing,
    /// and the failed reopen does not consume the entry, so the dead row would survive every attempt.
    private var recentClosedSessions: [RecentClosedItem] {
        library.recentClosedItems
            .filter { $0.kind == .session && $0.session != nil }
            .prefix(SessionSwitcher.maxCandidates)
            .map { $0 }
    }

    /// Title-bar button opening the recent-sessions popover — the mouse equivalent of the Ctrl-Tab switcher.
    /// Lists the window's most-recently-used OTHER sessions, then the recently CLOSED ones; disabled/dimmed
    /// only when BOTH are empty, so a window down to its last session still reaches what it just closed.
    /// Opening a popover is interactive-only, so it is control-API keep-in-sync exempt, like the bell opening
    /// the attention palette.
    var recentSessionsButton: some View {
        let empty = recentSessions.isEmpty && recentClosedSessions.isEmpty
        let enabled = !empty && pick.pending == nil
        return Button {
            guard pick.pending == nil else { return }
            recentSessionsShown.toggle()
        } label: {
            Label("Recent sessions", systemImage: "clock.arrow.circlepath")
        }
        .help("Recent and recently closed sessions (⌃Tab)")
        // pin the tint to chromeText like the attention bell: a disabled plain button otherwise resolves the SF
        // Symbol to the system disabled color, near-invisible on the themed titlebar — the dimmed clock would
        // vanish instead of graying out like the bell.
        .foregroundStyle(chromeText)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityIdentifier("recent-sessions-button")
        .popover(isPresented: $recentSessionsShown, arrowEdge: .bottom) {
            recentSessionsPopover
        }
        .onChange(of: recentSessionsShown) { _, shown in
            // suppress this window's auto-follow while the popover is open so an armed idle jump can't reshuffle
            // the MRU rows under the pointer (the palette + dashboard bracket the same way); the counted
            // suppression stays balanced across open/close and with the attention popover.
            if shown { store.suppressAutoFollow() } else { store.resumeAutoFollow() }
        }
        .onChange(of: empty) { _, isEmpty in
            // the only listed session exiting on its own fires no outside-click dismiss, so close the popover
            // ourselves when the list empties — else an empty sliver lingers under a now-disabled button.
            if isEmpty { recentSessionsShown = false }
        }
    }

    /// The recent-sessions popover body: the MRU OTHER sessions as full rows (the shared two-line
    /// `SessionSwitcherRow`), then the recently closed ones under a labelled divider. Each row highlights on
    /// hover and, on a click anywhere in the row, commits (`noteUserActivity` + `selectSession` + focus, like
    /// the Ctrl-Tab release; a closed row reopens first) then closes the popover — the palette-row feel.
    /// Tinted to the terminal theme (`terminalColor` panel, `chromeText` text, selection-color hover) so it
    /// matches the themed chrome rather than the system popover look.
    ///
    /// A labelled section rather than a segmented control: the two groups are read in one glance and clicked
    /// in one press, and a segment would put the more urgent list — what you just closed — behind a tab.
    private var recentSessionsPopover: some View {
        // no `.accessibilityIdentifier` on this container: a SwiftUI identifier on a parent propagates to and
        // OVERRIDES its descendants', clobbering the per-row `recent-session-row` ids the tests read.
        // both lists are capped at `SessionSwitcher.maxCandidates`, so the stack can reach twice the height
        // one list ever did and a title-bar-anchored popover that tall gets repositioned or clipped. The
        // scroller only engages past that bound; `.fixedSize` keeps a short list its natural height.
        ScrollView {
            VStack(spacing: 2) {
                ForEach(recentSessions, id: \.self) { id in
                    recentSessionRow(id)
                }
                if !recentClosedSessions.isEmpty {
                    if !recentSessions.isEmpty { Divider().padding(.vertical, 4) }
                    sectionHeader("Recently closed")
                    ForEach(recentClosedSessions) { item in
                        recentClosedRow(item)
                    }
                }
            }
        }
        .frame(maxHeight: GhosttyApp.shared.interfaceMetrics.scaled(420))
        .fixedSize(horizontal: false, vertical: true)
        .padding(6)
        .frame(width: GhosttyApp.shared.interfaceMetrics.scaled(320))
        .background(terminalColor)
        .presentationBackground(terminalColor)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(chromeText.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
            .accessibilityIdentifier("recent-closed-header")
    }

    /// One recently-closed session row. The subtitle carries the workspace it came from and the directory it
    /// will come back in, matching the live rows' `workspace · detail` shape.
    @ViewBuilder private func recentClosedRow(_ item: RecentClosedItem) -> some View {
        SessionPopoverRow(
            title: item.title,
            subtitle: "\(item.session?.workspaceName ?? "") · \(item.session?.snapshot.cwd ?? "")",
            status: nil,
            statusColorHex: nil,
            statusShape: nil,
            foreground: chromeText.opacity(0.8),
            hoverColor: recentSelectionColor,
            accessibilityID: "recent-closed-row"
        ) { reopenRecentClosed(item.id) }
    }

    @ViewBuilder private func recentSessionRow(_ id: UUID) -> some View {
        if let session = store.session(withID: id) {
            SessionPopoverRow(
                title: session.displayName,
                subtitle: "\(store.workspace(forSession: id)?.name ?? "") · \(session.subtitleDetail)",
                status: nil,
                statusColorHex: nil,
                statusShape: nil,
                foreground: chromeText,
                hoverColor: recentSelectionColor,
                accessibilityID: "recent-session-row"
            ) { selectRecent(id) }
        }
    }

    /// The hover-highlight color for a popover row: the terminal theme's selection background (the color the
    /// selected sidebar row uses), or a subtle wash of the foreground when the theme sets no selection color.
    private var recentSelectionColor: Color {
        if let sel = GhosttyApp.shared.terminalSelectionBackgroundColor {
            return Color(nsColor: sel).opacity(0.5)
        }
        return chromeText.opacity(0.2)
    }

    /// Commit a popover row click: note activity (so auto-follow can't pull the selection back), select the
    /// session, focus it, and close the popover — the mouse twin of the Ctrl-Tab release commit.
    private func selectRecent(_ id: UUID) {
        guard pick.pending == nil else { return }
        store.noteUserActivity()
        store.selectSession(id)
        actions.focusActiveSession()
        recentSessionsShown = false
    }

    /// Commit a recently-closed row click: rebuild the session (its pinned restore command included, so an
    /// agent pane comes back as that agent), select and focus it, then close the popover. `openRecentClosed`
    /// owns the reopen and the focus; the selection it leaves is the restored session.
    private func reopenRecentClosed(_ id: RecentClosedItem.ID) {
        guard pick.pending == nil else { return }
        store.noteUserActivity()
        actions.openRecentClosed(id)
        recentSessionsShown = false
    }

    /// Title-bar bell reflecting the window's attention state (opt-in, gated by the `attentionButtonEnabled`
    /// mirror). Three states from `store.attentionSessions`: empty → a dimmed disabled outline bell; non-empty
    /// with nothing blocked → a plain enabled bell in `chromeText`; any blocked session → a filled bell tinted
    /// the blocked-status color. No count, no pulse. Click opens the attention popover (the mouse form; ⌃⇧I /
    /// the Navigate menu keep the searchable `.attention` palette). Reading `store.attentionSessions` in the
    /// body registers the per-session `agentIndicator` observation, so the glyph re-renders live;
    /// `.accessibilityValue` (none|attention|blocked) exposes the otherwise-unobservable bell↔bell.fill state
    /// to XCUITest, mirroring `StatusIconView`.
    var attentionButton: some View {
        let sessions = store.attentionSessions
        let blocked = sessions.contains { $0.agentIndicator.status == .blocked }
        let empty = sessions.isEmpty
        let enabled = !empty && pick.pending == nil
        return Button {
            guard pick.pending == nil else { return }
            attentionPopoverShown.toggle()
        } label: {
            Label("Attention", systemImage: blocked ? "bell.fill" : "bell")
        }
        .foregroundStyle(blocked ? Color(nsColor: GhosttyApp.shared.blockedStatusColor) : chromeText)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .help(helpHint(empty ? "No sessions need attention" : "Show sessions that need attention", .showAttention))
        .accessibilityIdentifier("attention-button")
        .accessibilityValue(empty ? "none" : (blocked ? "blocked" : "attention"))
        .popover(isPresented: $attentionPopoverShown, arrowEdge: .bottom) {
            attentionPopover
        }
        .onChange(of: attentionPopoverShown) { _, shown in
            // same as the recent popover: suppress auto-follow while open (counted, so it stays balanced).
            if shown { store.suppressAutoFollow() } else { store.resumeAutoFollow() }
        }
        .onChange(of: empty) { _, isEmpty in
            // the last attention session going idle fires no outside-click dismiss; close the popover so no
            // empty sliver lingers under the now-disabled bell.
            if isEmpty { attentionPopoverShown = false }
        }
    }

    /// The attention popover body: the window's sessions needing attention (`store.attentionSessions`, sorted
    /// blocked→active→completed) as full-row `SessionPopoverRow`s with a leading status glyph — the mouse form
    /// of the ⌃⇧I attention palette, tinted and hover-highlighted like the recent-sessions popover. Clicking a
    /// row selects the session and reveals its blocked pane.
    private var attentionPopover: some View {
        VStack(spacing: 2) {
            ForEach(store.attentionSessions) { session in
                SessionPopoverRow(
                    title: session.displayName,
                    subtitle: "\(store.workspace(forSession: session.id)?.name ?? "") · \(session.subtitleDetail)",
                    status: session.agentIndicator.status,
                    statusColorHex: session.agentIndicator.color,
                    statusShape: session.agentIndicator.shape,
                    foreground: chromeText,
                    hoverColor: recentSelectionColor,
                    accessibilityID: "attention-session-row"
                ) { selectAttention(session.id) }
            }
        }
        .padding(6)
        .frame(width: GhosttyApp.shared.interfaceMetrics.scaled(320))
        .background(terminalColor)
        .presentationBackground(terminalColor)
    }

    /// Commit an attention popover row click: select the session and reveal its blocked pane (the pane that
    /// set the status), then close the popover — the mouse twin of the ⌃⇧I palette's select-and-reveal.
    private func selectAttention(_ id: UUID) {
        guard pick.pending == nil else { return }
        store.noteUserActivity()
        let indicator = store.selectSession(id)
        actions.revealActiveBlockedPane(captured: indicator)
        attentionPopoverShown = false
    }
}

/// One clickable session row for the title-bar popovers (recent-sessions and attention) — the shared two-line
/// `SessionSwitcherRow` tinted with the terminal theme (`foreground`), with an optional leading status glyph
/// (`status` plus its per-call `statusColorHex`/`statusShape` overrides, set only by the attention popover so
/// the row matches the sidebar glyph), a pointer-hover highlight (`hoverColor`) and a full-row hit area
/// (`.contentShape`), so the WHOLE row selects on click, not just the text. Kept a `Button` so it reads as an
/// actionable control to VoiceOver; `accessibilityID` distinguishes the two popovers' rows for the tests.
private struct SessionPopoverRow: View {
    let title: String
    let subtitle: String
    let status: AgentStatus?
    let statusColorHex: String?
    let statusShape: StatusShape?
    let foreground: Color
    let hoverColor: Color
    let accessibilityID: String
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            SessionSwitcherRow(title: title, subtitle: subtitle, foreground: foreground,
                               status: status, statusColorHex: statusColorHex, statusShape: statusShape)
                .background(hovering ? hoverColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityIdentifier(accessibilityID)
    }
}
