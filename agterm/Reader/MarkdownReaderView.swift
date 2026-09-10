import AppKit
import agtermCore
import os
import WebKit

/// One session's markdown reader panel: a `WKWebView` running the bundled `Resources/reader` page
/// (markdown-it, DOMPurify, idiomorph) fed the file's text, re-fed on every change the watcher sees.
/// Ported from `WebPane.swift`/`ReaderView.swift` in `~/mmee/reader`; names stay close so a fix there
/// can be mirrored here.
///
/// Evals are queued until the page posts `ready`, since `render` before the scripts have run is lost. The
/// page's `<base>` is retargeted to the file's folder so relative images resolve, which is why every
/// resource of the page itself is loaded by absolute URL and why `loadFileURL` grants read access to `/`.
@MainActor
final class MarkdownReaderView: NSView {
    private static let logger = Logger(subsystem: Brand.bundleID, category: "MarkdownReader")
    private static let messageNames = ["ready", "outline", "active", "title", "error"]

    private(set) var path: String
    private let web: ReaderWebView
    private var fontSize = MarkdownReaderView.defaultFontSize
    private let bridge = Bridge()
    private var watcher: ReaderFileWatcher?
    private var text = ""
    private var appliedBackground: NSColor?
    private let missingBanner = NSTextField(labelWithString: "file is gone from disk")
    /// Called after the document was handed to the standalone reader, so the owner can take the pane down.
    var onPopOut: (() -> Void)?
    /// The web view gained (true) or lost first responder; the owner mirrors it into split focus.
    var onFocusChange: ((Bool) -> Void)?
    /// A pane is narrower and closer than the standalone window, so the page runs smaller and tighter than
    /// its own 17px/64px defaults; ⌘+/⌘−/⌘0 step and reset from here, like a terminal's font zoom.
    static let defaultFontSize = 14
    private static let fontSizeRange = 10...28
    private static let embeddedCSS = ".md{padding:28px 28px 30vh}"
    /// The standalone MmeeReader (`~/mmee/reader`); the system's `.md` handler stands in when it is absent.
    static let standaloneReaderBundleID = "uz.marshub.mmee.reader"

    /// The bundled page's folder; nil when the build did not bundle it, in which case the panel says so
    /// instead of showing a blank web view.
    static func webDir() -> URL? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("reader"),
              FileManager.default.isReadableFile(atPath: dir.appendingPathComponent("index.html").path)
        else { return nil }
        return dir
    }

    init(path: String) {
        self.path = path
        let config = WKWebViewConfiguration()
        for name in Self.messageNames { config.userContentController.add(bridge, name: name) }
        web = ReaderWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        bridge.owner = self
        web.onFocusChange = { [weak self] focused in self?.onFocusChange?(focused) }
        web.navigationDelegate = bridge
        web.allowsMagnification = true
        if #available(macOS 13.3, *) { web.isInspectable = true }
        web.translatesAutoresizingMaskIntoConstraints = false
        addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor),
            web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        installMissingBanner()
        installPopOutButton()
        eval("document.head.appendChild(Object.assign(document.createElement('style'), {textContent: \(Self.embeddedCSS.readerJS)}))")
        eval("setSize(\(fontSize))")
        if let dir = Self.webDir() {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: URL(fileURLWithPath: "/"))
        } else {
            Self.logger.error("reader page is not bundled in this build")
            web.loadHTMLString("<p style='font: 13px -apple-system; padding: 1em'>reader page is not bundled</p>",
                               baseURL: nil)
        }
        load(path: path)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    /// Points the panel at `path`: re-arms the watcher, retargets the page's base to the file's folder and
    /// renders the text. Same-path calls are a plain reread.
    func load(path: String) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        watcher?.cancel()
        watcher = ReaderFileWatcher(url: url, onChange: { [weak self] in self?.reread() },
                                    onMissing: { [weak self] missing in
                                        self?.missingBanner.isHidden = !missing
                                        if !missing { self?.reread() }
                                    })
        text = ""
        eval("setBase(\(url.deletingLastPathComponent().absoluteString.readerJS))")
        reread()
    }

    /// Tints the page to the terminal beside it: the page's `--bg` becomes the terminal background, and the
    /// view's appearance follows that color's luminance so `prefers-color-scheme` picks the matching palette
    /// (the page's own dark/light split follows the SYSTEM otherwise, which a dark terminal on a light desk
    /// turned into a white sheet). Idempotent; a nil color leaves the page on its own palette.
    func apply(background: NSColor?) {
        guard let background, background != appliedBackground,
              let srgb = background.usingColorSpace(.sRGB) else { return }
        appliedBackground = background
        let luminance = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
        appearance = NSAppearance(named: luminance < 0.5 ? .darkAqua : .aqua)
        let hex = String(format: "#%02x%02x%02x", Int(srgb.redComponent * 255 + 0.5),
                         Int(srgb.greenComponent * 255 + 0.5), Int(srgb.blueComponent * 255 + 0.5))
        eval("document.documentElement.style.setProperty('--bg', \(hex.readerJS))")
    }

    /// The reader whose web view holds the key window's first responder: the font chords act on the pane
    /// the user is in, and a focused document is that pane even though no terminal surface is.
    static func focused() -> MarkdownReaderView? {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let current = view {
            if let reader = current as? MarkdownReaderView { return reader }
            view = current.superview
        }
        return nil
    }

    func adjustFontSize(by step: Int) { setFontSize(fontSize + step) }
    func resetFontSize() { setFontSize(Self.defaultFontSize) }

    private func setFontSize(_ size: Int) {
        fontSize = min(max(size, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        eval("setSize(\(fontSize))")
    }

    /// Frees the web view: the message handlers hold the bridge strongly through the content controller,
    /// so without removing them the whole panel would leak past its session.
    func teardown() {
        watcher?.cancel()
        watcher = nil
        for name in Self.messageNames { web.configuration.userContentController.removeScriptMessageHandler(forName: name) }
        web.navigationDelegate = nil
        web.stopLoading()
        web.removeFromSuperview()
    }

    private func reread() {
        guard let fresh = try? String(contentsOfFile: path, encoding: .utf8), fresh != text else { return }
        text = fresh
        eval("render(\(fresh.readerJS))")
    }

    private func eval(_ js: String) {
        guard bridge.ready else { bridge.pending.append(js); return }
        web.evaluateJavaScript(js) { _, error in
            if let error { Self.logger.error("js: \(error.localizedDescription, privacy: .public)") }
        }
    }

    fileprivate func flushPending() {
        bridge.ready = true
        let queued = bridge.pending
        bridge.pending = []
        queued.forEach(eval)
    }

    /// Hands the document to the standalone reader app in its own window and reports it, so the split pane
    /// goes back to the shell: the pane is for reading beside the work, the window for reading at length.
    @objc private func popOut() {
        let url = URL(fileURLWithPath: path)
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.standaloneReaderBundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
        onPopOut?()
    }

    private func installPopOutButton() {
        let button = NSButton(title: "Open in Reader", target: self, action: #selector(popOut))
        button.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.toolTip = "Open this file in its own Reader window and give the pane back to the shell"
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    private func installMissingBanner() {
        missingBanner.font = .systemFont(ofSize: 11.5, weight: .medium)
        missingBanner.textColor = .systemOrange
        missingBanner.isHidden = true
        missingBanner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(missingBanner)
        NSLayoutConstraint.activate([
            missingBanner.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            missingBanner.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    /// The page's side of the bridge. Not the view itself because `WKUserContentController` retains its
    /// handlers, and a view retaining its own content controller would never deinit.
    /// On macOS the `WKWebView` itself is the responder, so first-responder transitions are observable here
    /// the way `GhosttySurfaceView` observes its own; this is what lets a click in the document read as a
    /// pane focus.
    private final class ReaderWebView: WKWebView {
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            if result { onFocusChange?(true) }
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { onFocusChange?(false) }
            return result
        }
    }

    private final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var owner: MarkdownReaderView?
        var ready = false
        var pending: [String] = []

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "ready": owner?.flushPending()
            case "error": MarkdownReaderView.logger.error("page: \((message.body as? String) ?? "", privacy: .public)")
            default: break
            }
        }

        /// Only the bundled page itself may load in the panel. A clicked web link opens in the browser, a
        /// clicked file opens in whatever handles it (another `.md` lands in the user's markdown app); the
        /// panel shows the document an agent named and nothing else.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if action.navigationType != .linkActivated {
                let shell = MarkdownReaderView.webDir()?.appendingPathComponent("index.html").standardizedFileURL
                return decisionHandler(url.readerDeletingFragment().standardizedFileURL == shell ? .allow : .cancel)
            }
            if url.isFileURL, url.readerDeletingFragment() == web.url?.readerDeletingFragment() {
                return decisionHandler(.allow)
            }
            if ["http", "https", "mailto"].contains(url.scheme ?? "") || url.isFileURL {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}

private extension String {
    /// The string as a JavaScript literal; JSON encoding is a valid JS string literal for every scalar.
    var readerJS: String {
        let data = (try? JSONEncoder().encode(self)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

private extension URL {
    func readerDeletingFragment() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url ?? self
    }
}
