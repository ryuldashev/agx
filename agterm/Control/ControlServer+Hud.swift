import AppKit
import CoreText
import Foundation
import agtermCore

/// App-side host for `session.hud.*`. Validation, error text and response shape stay in
/// `ControlDispatcher+Hud`; this layer supplies the two things agtermCore cannot resolve — the terminal
/// font's cell size and the pane's live geometry — which size the panel's width budget and the read-back.
extension ControlServer {
    func openHud(_ target: String?, window: String?, spec: HudSpec) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            guard let session = store.session(withID: id) else {
                return ControlResponse(ok: false, error: "no such session")
            }
            guard store.openHud(id, spec: spec, size: HudLayout.panelSize(for: spec, pane: self.paneMetrics(for: session))) else {
                return ControlResponse(ok: false, error: "overlay already open")
            }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }

    /// Rewrites the live HUD's message and re-sizes the panel in place.
    func updateHud(_ target: String?, window: String?, spec: HudSpec) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            guard let session = store.session(withID: id), session.hudActive else {
                return ControlResponse(ok: false, error: OverlayHudError.noHud)
            }
            store.updateHud(id, spec: spec, size: HudLayout.panelSize(for: spec, pane: self.paneMetrics(for: session)))
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }

    /// Every close — this one, `overlay close`, ⌘W, session and window teardown — clears the HUD's state.
    func closeHud(_ target: String?, window: String?) -> ControlResponse {
        resolver.resolveSession(target, window: window) { store, id in
            guard store.closeHud(id) else {
                return ControlResponse(ok: false, error: OverlayHudError.noHud)
            }
            return ControlResponse(ok: true, result: ControlResult(id: id.uuidString))
        }
    }

    /// The terminal's padding inside the pane, per side, from `Resources/ghostty-defaults.conf`
    /// (`window-padding-x = 8`, `window-padding-y = 6`). A user `ghostty.conf` overriding either is not
    /// tracked and shifts the measured percent by about a column, as the estimated cell already can.
    private static let windowPadding = (horizontal: 8.0, vertical: 6.0)

    /// Cell size from the CONFIGURED terminal font (the session's own size override, else the Settings
    /// base) and pane size from the surfaces currently laid out. libghostty reports no cell metrics —
    /// `GHOSTTY_ACTION_CELL_SIZE` discards its payload — so this measurement may round differently from the
    /// cell it actually renders. That divergence is ACCEPTED, not corrected: the min/max clamp only bounds
    /// the percentage, and the native panel wraps its text inside whatever width that gives it. A session
    /// with nothing on screen measures zero and takes the clamp's maximum.
    func paneMetrics(for session: Session) -> PaneMetrics {
        let cell = Self.cellSize(family: settingsModel.settings.fontFamily,
                                 size: session.fontSize ?? GhosttyApp.shared.baseFontSize)
        // the panel is laid out over the whole detail area, so the pane is the union of the laid-out panes:
        // a hidden-but-focused split shows one pane maximized, and only the one in a window measures right.
        let frames = [session.surface, session.splitSurface]
            .compactMap { $0 as? GhosttySurfaceView }
            .filter { $0.window != nil }
            .map { $0.convert($0.bounds, to: nil) }
        let area = frames.dropFirst().reduce(frames.first ?? .zero) { $0.union($1) }
        return PaneMetrics(cellWidth: cell.width, cellHeight: cell.height,
                           paneWidth: area.width, paneHeight: area.height,
                           paddingWidth: Self.windowPadding.horizontal,
                           paddingHeight: Self.windowPadding.vertical)
    }

    /// One cell of `family` at `size`: the horizontal advance of a digit (every glyph advances the same in
    /// a monospaced face) and ascent + descent + leading for the line box. An unresolvable family falls
    /// back to the system monospaced face rather than to a guessed ratio.
    static func cellSize(family: String?, size: Double) -> (width: Double, height: Double) {
        let font = family.flatMap { NSFont(name: $0, size: size) }
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        var characters: [UniChar] = Array("0".utf16)
        var glyph = CGGlyph()
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(font, &characters, &glyph, 1) {
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        } else {
            // a face with no glyph for "0" would otherwise leave the advance at zero and drive every panel to
            // the clamp's floor with nothing to explain it
            NSLog("hud: no digit glyph in %@, falling back to a one-point cell", font.fontName)
        }
        let height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        return (width: max(advance.width, 1), height: max(height, 1))
    }
}
