import AppKit
import agtermCore
import os

private let logger = Logger(subsystem: Brand.bundleID, category: "WatermarkRenderer")

/// Turns a `BackgroundWatermark` into a PNG file path for libghostty's `background-image`: `.image`
/// validates and returns the user's file, `.text` rasterizes the string (Core Text on a transparent canvas)
/// to a per-session PNG in the state dir for `background-image-fit` to scale to the surface. AppKit-only and
/// `@MainActor` (it reads the live terminal foreground for the default text tint), so it lives in the app
/// target, not the host-free `agtermCore`.
@MainActor
enum WatermarkRenderer {
    /// The image formats libghostty reads (Config.zig: PNG or JPEG only).
    static func isSupportedImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg"].contains((path as NSString).pathExtension.lowercased())
    }

    /// The resolved PNG/JPEG path for `watermark`, rendering the `.text` PNG as a side effect:
    /// - `.image` → the user's file path (nil if missing or an unsupported format);
    /// - `.text` → a per-session PNG in `WatermarkStorage.directoryURL()` rendered from the string + color
    ///   (nil if the text is empty/over-length or rendering fails);
    /// - `.color` → nil (a solid color needs no image; `WatermarkConfig.overlayText` emits `background`).
    /// Returns nil for a nil watermark. Re-rendered on every call so a `.text` PNG always reflects the
    /// current string/color (cheap; called only on set/clear/reload, not per frame).
    static func materialize(_ watermark: BackgroundWatermark?, sessionID: UUID) -> String? {
        guard let watermark else { return nil }
        switch watermark.kind {
        case .color:
            return nil
        case .image:
            // re-validate the path (control-char guard) here too, not only at the control boundary — a
            // persisted spec restored from a hand-edited snapshot reaches this path without re-validation.
            guard let path = watermark.imagePath, WatermarkConfig.isValidImagePath(path),
                  isSupportedImage(path), FileManager.default.fileExists(atPath: path) else { return nil }
            return path
        case .text:
            guard let text = watermark.text, WatermarkConfig.isValidText(text) else { return nil }
            let color = NSColor(agtermHex: watermark.colorHex) ?? GhosttyApp.shared.terminalForegroundColor ?? .white
            WatermarkStorage.ensureDirectory()
            let url = WatermarkStorage.renderedTextURL(sessionID: sessionID)
            return renderText(text, color: color, to: url) ? url.path : nil
        }
    }

    /// The horizontally flipped copy of `path`, rendered once into the watermark dir and reused while the
    /// source is unchanged (`WatermarkStorage.mirroredImageURL` keys on path + mtime). libghostty has no
    /// mirror key, so the flip has to exist as pixels. Returns nil when the source can't be read or the copy
    /// can't be written — callers fall back to the unflipped path rather than dropping the background.
    static func mirroredCopy(of path: String) -> String? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        let url = WatermarkStorage.mirroredImageURL(sourcePath: path, modified: modified)
        if FileManager.default.fileExists(atPath: url.path) { return url.path }
        guard let source = NSImage(contentsOfFile: path),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.warning("watermark mirror: source unreadable")
            return nil
        }
        let width = cgImage.width, height = cgImage.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let flipped = context.makeImage() else { return nil }
        WatermarkStorage.ensureDirectory()
        let rep = NSBitmapImageRep(cgImage: flipped)
        guard let data = rep.representation(using: .png, properties: [:]), (try? data.write(to: url)) != nil else {
            logger.warning("watermark mirror: PNG write failed")
            return nil
        }
        return url.path
    }

    /// Rasterize `text` in `color` onto a transparent PNG sized to the glyphs plus padding, at a large fixed
    /// resolution so `background-image-fit = contain` scales it up crisply to fill the terminal. Transparent,
    /// so only the glyphs composite over it; translucency comes from `background-image-opacity`, not pixels.
    private static func renderText(_ text: String, color: NSColor, to url: URL) -> Bool {
        let fontSize: CGFloat = 256
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let padding = fontSize * 0.3
        let width = Int((textSize.width + padding * 2).rounded(.up))
        let height = Int((textSize.height + padding * 2).rounded(.up))
        // belt-and-suspenders ceiling on top of the WatermarkConfig.maxTextLength input cap: never attempt
        // an absurd bitmap allocation even if the font/cap changes (64 Mpx ≈ 256 MB at 4 bytes/px).
        let maxPixels = 64_000_000
        guard width > 0, height > 0, width * height <= maxPixels,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            // not a client error (text length is capped at the boundary): a degenerate/oversized canvas or a
            // bitmap allocation failure — Warn, since the watermark silently won't appear with no other signal.
            logger.warning("watermark text bitmap alloc failed (\(width, privacy: .public)x\(height, privacy: .public))")
            return false
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        attributed.draw(at: NSPoint(x: padding, y: padding))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else {
            logger.warning("watermark text PNG encoding failed")
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            logger.warning("watermark text PNG write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
