import Foundation

// MARK: - Workspace defaults

/// Reading and writing the per-workspace new-session seed (`WorkspaceDefaults`). Kept out of the main
/// `AppStore` body for the file-size budget, like the other `AppStore+*.swift` concerns.
extension AppStore {

    /// The defaults pinned on a workspace, empty for an unknown id — so every caller can read without
    /// unwrapping and an id that lost its workspace mid-flight degrades to "no defaults".
    public func workspaceDefaults(_ workspaceID: UUID) -> WorkspaceDefaults {
        workspaces.first { $0.id == workspaceID }?.defaults ?? WorkspaceDefaults()
    }

    /// Replaces a workspace's defaults and persists. False when no workspace matches. An empty value is
    /// stored as empty (which `snapshot()` then omits), so clearing both fields is a normal write.
    @discardableResult
    public func setWorkspaceDefaults(_ defaults: WorkspaceDefaults, forWorkspace workspaceID: UUID) -> Bool {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return false }
        guard workspaces[index].defaults != defaults else { return true }
        workspaces[index].defaults = defaults
        save()
        return true
    }

    /// The directory and command a new session in `workspaceID` starts with: an explicit request wins,
    /// then the workspace default, then `fallbackCwd` (the global new-session-directory setting for the
    /// GUI, `$HOME` for the control channel). `agents` is the connected-agent list from settings; the
    /// store is host-free and cannot read `settings.json` itself.
    public func newSessionSeed(workspaceID: UUID, requestedCwd: String? = nil, requestedCommand: String? = nil,
                               fallbackCwd: String, agents: [AgentDefinition],
                               home: String = NSHomeDirectory()) -> (cwd: String, command: String?) {
        let defaults = workspaceDefaults(workspaceID)
        return (NewSessionSeed.cwd(requested: requestedCwd, defaults: defaults, fallback: fallbackCwd, home: home),
                NewSessionSeed.command(requested: requestedCommand, defaults: defaults, agents: agents))
    }
}
