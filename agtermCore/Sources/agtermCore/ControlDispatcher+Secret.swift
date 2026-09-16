import Foundation

/// Limits on what a secret may be, shared by `secret.add` and the palette's Add Secret prompt so the two
/// refuse the same input with the same words. A label is a keychain account name the palette lists and the
/// CLI types; a value is typed as keystrokes, so anything a keystroke cannot carry is refused up front.
public enum SecretPolicy {
    public static let maxLabelLength = 64
    public static let maxValueLength = 4096

    /// Why a trimmed, non-empty `label` is unusable, or nil. The empty case is the caller's: its wording
    /// names the command or the field.
    public static func labelError(_ label: String) -> String? {
        if label.count > maxLabelLength { return "label too long (max \(maxLabelLength) characters)" }
        if containsControlCharacters(label) { return "label must not contain control characters" }
        return nil
    }

    /// Why a non-empty `value` is unusable, or nil.
    public static func valueError(_ value: String) -> String? {
        if value.count > maxValueLength { return "value too long (max \(maxValueLength) characters)" }
        if containsControlCharacters(value) { return "value must not contain control characters" }
        return nil
    }

    static func containsControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }
}

extension ControlDispatcher {
    /// Validates `secret.*` host-free. The keychain itself lives app-side; the value is never echoed.
    func dispatchSecretCommand(_ request: ControlRequest) async -> ControlResponse {
        switch request.cmd {
        case .secretList:
            return actions.secretList()
        case .secretAdd:
            switch validLabel(request, verb: "secret.add") {
            case .failed(let response): return response
            case .ok(let label):
                guard let value = request.args?.value, !value.isEmpty else {
                    return ControlResponse(ok: false, error: "secret.add requires a value")
                }
                if let error = SecretPolicy.valueError(value) { return ControlResponse(ok: false, error: error) }
                return actions.secretAdd(label: label, value: value)
            }
        case .secretRemove:
            switch validLabel(request, verb: "secret.remove") {
            case .failed(let response): return response
            case .ok(let label): return actions.secretRemove(label: label)
            }
        case .secretInsert:
            switch validLabel(request, verb: "secret.insert") {
            case .failed(let response): return response
            case .ok(let label):
                if let pane = request.args?.pane, !["left", "right", "scratch"].contains(pane) {
                    return ControlResponse(ok: false, error: "invalid pane: \(pane)")
                }
                return await actions.secretInsert(label: label, target: request.target,
                                                  window: request.args?.window, pane: request.args?.pane)
            }
        default:
            preconditionFailure("dispatchSecretCommand called for \(request.cmd.rawValue)")
        }
    }

    private enum LabelCheck {
        case ok(String)
        case failed(ControlResponse)
    }

    private func validLabel(_ request: ControlRequest, verb: String) -> LabelCheck {
        guard let label = request.args?.label.trimmedOrNilValue else {
            return .failed(ControlResponse(ok: false, error: "\(verb) requires a label"))
        }
        if let error = SecretPolicy.labelError(label) { return .failed(ControlResponse(ok: false, error: error)) }
        return .ok(label)
    }
}
