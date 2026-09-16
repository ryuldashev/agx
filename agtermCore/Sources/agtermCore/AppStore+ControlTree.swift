import Foundation

// MARK: - Control tree projection

/// The `tree` payload: this store's workspace/session model as the control channel sees it. Split out of
/// the main `AppStore` body for the file-size budget, like `AppStore+Snapshot.swift`; the host supplies
/// every platform-specific lookup (live foreground process, font sizes, dashboard state, the agent name
/// behind a workspace default) as a closure, so the projection itself stays host-free.
extension AppStore {

    /// Projects this store's workspace/session model into the control-channel `tree` payload. Foreground
    /// command lookup is supplied by the host because live process inspection is platform-specific.
    public func controlTree(foreground: (Session) -> [String]? = { _ in nil },
                            splitForeground: (Session) -> [String]? = { _ in nil },
                            fontSize: (Session) -> Double? = { _ in nil },
                            splitFontSize: (Session) -> Double? = { _ in nil },
                            scratchFontSize: (Session) -> Double? = { _ in nil },
                            quickVisible: () -> Bool? = { nil },
                            zoomedSurface: () -> String? = { nil },
                            pickPending: () -> String? = { nil },
                            dashboardMembers: () -> [String]? = { nil },
                            dashboardHighlighted: () -> String? = { nil },
                            dashboardFontSize: () -> Double? = { nil },
                            dashboardFontMode: () -> String? = { nil },
                            workspaceDefaults: (WorkspaceDefaults) -> ControlWorkspaceDefaults? = { _ in nil },
                            scheduled: () -> [ControlScheduledNode]? = { nil })
    -> ControlTree {
        let activeID = selectedSessionID
        // `currentWorkspaceID`, not the selected session's owner: an EMPTY destination selects nothing, so
        // deriving this from the selection alone made `tree` name the workspace `workspace.go` just left.
        let activeWorkspaceID = currentWorkspaceID
        let nodes = workspaces.map { workspace in
            let sessions = workspace.sessions.map { session in
                let idle = session.agentIndicator.status == .idle
                let status = idle ? nil : session.agentIndicator.status.rawValue
                let statusPane = idle ? nil : session.agentIndicator.statusPane?.rawValue
                let surfaces = TerminalZoomSurface.allCases.compactMap { surface -> ControlSurfaceNode? in
                    guard surface.isAvailable(in: session) else { return nil }
                    let id = TerminalSurfaceID(sessionID: session.id, surface: surface).rawValue
                    return ControlSurfaceNode(id: id, kind: surface.rawValue,
                                              active: surface.isActive(in: session),
                                              visible: surface.isVisible(in: session))
                }
                return ControlSessionNode(id: session.id.uuidString, name: session.displayName,
                                          cwd: session.effectiveCwd, title: session.oscTitle,
                                          active: session.id == activeID,
                                          split: session.isSplit,
                                          hasSplit: session.hasSplit ? true : nil,
                                          splitAxis: session.hasSplit ? session.splitAxis.rawValue : nil,
                                          splitRatio: session.hasSplit ? session.splitRatio : nil,
                                          splitFocused: session.hasSplit ? session.splitFocused : nil,
                                          overlay: session.programOverlayActive,
                                          overlaySizePercent: session.programOverlayActive
                                              ? session.overlaySizePercent : nil,
                                          paneOverlays: paneOverlays(session),
                                          hud: hudNode(session),
                                          reader: readerNode(session),
                                          failover: ControlFailoverNode.project(session.failover),
                                          autoAnswer: autoAnswerNode(session),
                                          scratch: session.scratchActive, flagged: session.flagged,
                                          commandWait: (session.initialCommand != nil && session.commandWait) ? true : nil,
                                          durable: session.durable ? true : nil,
                                          attached: session.durable ? session.durableAttached : nil,
                                          foreground: foreground(session),
                                          splitForeground: splitForeground(session),
                                          // the PERSISTED overrides, not the transient pending payloads, so
                                          // a read after one fired still reports what stays pinned.
                                          restoreCommand: session.restoreCommand,
                                          splitRestoreCommand: session.splitRestoreCommand, status: status,
                                          statusPane: statusPane,
                                          statusBlink: idle ? nil : (session.agentIndicator.blink ? true : nil),
                                          statusColor: idle ? nil : session.agentIndicator.color,
                                          statusShape: idle ? nil : session.agentIndicator.shape?.rawValue,
                                          background: session.backgroundWatermark,
                                          unseen: session.unseenCount > 0 ? session.unseenCount : nil,
                                          fontSize: fontSize(session),
                                          splitFontSize: splitFontSize(session),
                                          scratchFontSize: scratchFontSize(session),
                                          surfaces: surfaces,
                                          // host-free: `isRealized` is on `TerminalSurface`, so this needs
                                          // no app-side closure like the font sizes above. An empty slot is
                                          // false, not omitted — "no terminal" either way to a caller.
                                          realized: session.surface?.isRealized ?? false)
            }
            return ControlWorkspaceNode(id: workspace.id.uuidString, name: workspace.name,
                                        active: workspace.id == activeWorkspaceID,
                                        focused: focusedWorkspaceIDs.contains(workspace.id) ? true : nil,
                                        collapsed: workspace.isExpanded ? nil : true,
                                        // omitted when the workspace pins nothing, like `collapsed`; the
                                        // agent's NAME needs settings, so the host supplies the projection.
                                        defaults: workspaceDefaults(workspace.defaults)?.nonEmpty,
                                        sessions: sessions)
        }
        return ControlTree(workspaces: nodes, idleMs: idleMs(), autoFollowMs: autoFollowMs,
                           sidebarVisible: sidebarVisible, sidebarMode: sidebarMode.rawValue,
                           workspaceFilter: focusEnabled,
                           quickVisible: quickVisible(), zoomedSurface: zoomedSurface(),
                           dashboardMembers: dashboardMembers(),
                           dashboardHighlighted: dashboardHighlighted(),
                           dashboardFontSize: dashboardFontSize(),
                           dashboardFontMode: dashboardFontMode(),
                           pickPending: pickPending(),
                           scheduled: scheduled())
    }

    /// The tree's `paneOverlays`: the panes covered by their own overlay, omitted when neither is.
    private func paneOverlays(_ session: Session) -> [String]? {
        let panes = session.openPaneOverlays.map(\.rawValue)
        return panes.isEmpty ? nil : panes
    }

    /// The tree's `autoAnswer`, the read side of `session.autoanswer`; also the command's own answer. A
    /// grace only counts while the session is still `blocked`: a keystroke clears the status without
    /// telling the coordinator, whose timer then finds nothing to do, so the running `dueAt` is masked here.
    public func autoAnswerNode(_ session: Session) -> ControlAutoAnswerNode {
        var state = session.autoAnswer
        if session.agentIndicator.status != .blocked { state.dueAt = nil }
        return ControlAutoAnswerNode.project(state, settingsEnabled: autoAnswerEnabled,
                                             delaySeconds: autoAnswerDelaySeconds)
    }

    /// The tree's `reader`: the document in the split pane, omitted when no reader is up. Its width is the
    /// node's `splitRatio`, so nothing is repeated here.
    private func readerNode(_ session: Session) -> ControlReaderNode? {
        session.readerSpec.map { ControlReaderNode(path: $0.path) }
    }

    /// The tree's `hud`: the live panel's spec carrying the slot's EFFECTIVE size on BOTH axes and the
    /// effective position, omitted when no HUD occupies the slot.
    private func hudNode(_ session: Session) -> ControlHudNode? {
        guard session.hudActive, let spec = session.hudSpec else { return nil }
        return ControlHudNode(message: spec.message, detail: spec.detail,
                              spinner: spec.spinner?.rawValue ?? HudSpinner.noneName,
                              backgroundColor: spec.backgroundColor, textColor: spec.textColor,
                              sizePercent: session.overlaySizePercent,
                              heightPercent: session.hudHeightPercent, position: spec.position.rawValue,
                              reveal: spec.reveal?.uuidString)
    }
}
