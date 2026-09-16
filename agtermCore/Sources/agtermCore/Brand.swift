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
    /// `kSecAttrService` of the secrets the Insert Secret palette types (`secret.*`). One item per label in the
    /// login keychain, so Keychain Access lists them under this name and a fork's items never collide.
    public static let keychainService = "uz.marshub.agx.secrets"
    /// Upstream agterm's config directory, seeded ON FIRST RUN when this fork has none of its own — a
    /// fork of a tool you already use should start with the keymap you already wrote.
    public static let legacyConfigDirectoryName = "agterm"

    /// What the About panel and the Help menu say about this build.
    public static let productName = "agx"
    public static let homepage = "https://github.com/ryuldashev/agx"
    public static let copyright = "© 2026 Ruslan Yuldashev"
    /// The project this is a fork of. MIT asks that the origin stays visible, and it should anyway.
    public static let upstreamName = "agterm"
    public static let upstreamAuthor = "Umputun"
    public static let upstreamHomepage = "https://agterm.com"
    public static let upstreamDocs = "https://agterm.com/docs"
}
