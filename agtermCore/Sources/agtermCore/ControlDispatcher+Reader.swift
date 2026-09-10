import Foundation

extension ControlDispatcher {
    /// Validates host-free reader arguments: the path's text, the anchor and the width. Whether the file
    /// exists and is readable needs the host's file system and stays app-side.
    func dispatchReaderCommand(_ request: ControlRequest) -> ControlResponse {
        if request.cmd == .sessionReaderClose {
            return actions.closeReader(request.target, window: request.args?.window)
        }
        let args = request.args
        guard let path = args?.path, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ControlResponse(ok: false, error: ReaderError.requiresPath)
        }
        guard !containsControlCharacters(path) else {
            return ControlResponse(ok: false, error: "reader path must not contain control characters")
        }
        // the CLI absolutizes against the caller's cwd; a raw-socket relative path has no cwd to resolve
        // against, and the host must never guess one.
        guard path.hasPrefix("/") else {
            return ControlResponse(ok: false, error: "reader path must be absolute: \(path)")
        }
        if let percent = args?.sizePercent, !(1...100).contains(percent) {
            return ControlResponse(ok: false, error: "session.reader.open: --size-percent must be 1...100")
        }
        var position = ReaderLayout.defaultPosition
        if let raw = args?.position {
            guard let parsed = HudPosition.parse(raw) else {
                return ControlResponse(ok: false,
                                       error: "invalid position: \(raw) (\(HudPosition.acceptedNamesList))")
            }
            position = parsed
        }
        return actions.openReader(request.target, window: args?.window,
                                  spec: ReaderSpec(path: path, position: position,
                                                   sizePercent: args?.sizePercent ?? ReaderLayout.defaultSizePercent))
    }
}
