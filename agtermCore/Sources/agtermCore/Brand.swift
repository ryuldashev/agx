import Foundation

/// Who this build is, in one place. A fork's whole identity — bundle id, state directory, config
/// directory, control socket — is derived from here, so renaming the product is a change to this file
/// and nothing else.
///
/// The values deliberately differ from upstream agterm's so both can be installed and RUN at the same
/// time: state, settings and the control socket are path-based, so distinct directory names are what
/// actually keeps two running apps from writing each other's session tree.
///
/// What deliberately does NOT change: the `AGTERM_*` environment variables a session inherits and
/// `TERM_PROGRAM`. Every agent hook, cookbook recipe and shell integration written for agterm keys off
/// those names; a session addresses THIS app because `AGTERM_SOCKET` points at this app's socket, not
/// because the variable is spelled differently.
public enum Brand {
    /// Reverse-DNS id: the bundle identifier, `Logger` subsystem, dispatch-queue and pasteboard prefixes.
    public static let bundleID = "uz.marshub.agx"
    /// Directory under `~/Library/Application Support` holding the session tree, settings and the socket.
    public static let stateDirectoryName = "agx"
    /// Directory under `~/.config` holding the user-editable `keymap.conf` and `ghostty.conf`.
    public static let configDirectoryName = "agx"
    /// The control socket's filename inside the state directory.
    public static let socketFileName = "agx.sock"
    /// Upstream agterm's config directory, seeded ON FIRST RUN when this fork has none of its own — a
    /// fork of a tool you already use should start with the keymap you already wrote.
    public static let legacyConfigDirectoryName = "agterm"
}
