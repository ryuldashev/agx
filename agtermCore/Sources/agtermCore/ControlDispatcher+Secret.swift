import Foundation

/// Limits on what `secret.add` stores. A label is a keychain account name the palette lists and the CLI
/// types; a value is typed as keystrokes, so anything a keystroke cannot carry is refused up front.
public enum SecretPolicy {
    public static let maxLabelLength = 64
    public static let maxValueLength = 4096
}

extension ControlDispatcher {
    /// Validates `secret.*` host-free. The keychain itself lives app-side; the value is never echoed.
    func dispatchSecretCommand(_ request: ControlRequest) async -> ControlResponse {
        switch request.cmd {
        case .secretList:
            return actions.secretList()
        case .secretAdd:
            guard let label = validLabel(request) else {
                return ControlResponse(ok: false, error: labelError(request, verb: "secret.add"))
            }
            guard let value = request.args?.value, !value.isEmpty else {
                return ControlResponse(ok: false, error: "secret.add requires a value")
            }
            guard value.count <= SecretPolicy.maxValueLength else {
                return ControlResponse(ok: false, error: "value too long (max \(SecretPolicy.maxValueLength) characters)")
            }
            guard !containsControlCharacters(value) else {
                return ControlResponse(ok: false, error: "value must not contain control characters")
            }
            return actions.secretAdd(label: label, value: value)
        case .secretRemove:
            guard let label = validLabel(request) else {
                return ControlResponse(ok: false, error: labelError(request, verb: "secret.remove"))
            }
            return actions.secretRemove(label: label)
        case .secretInsert:
            guard let label = validLabel(request) else {
                return ControlResponse(ok: false, error: labelError(request, verb: "secret.insert"))
            }
            if let pane = request.args?.pane, !["left", "right", "scratch"].contains(pane) {
                return ControlResponse(ok: false, error: "invalid pane: \(pane)")
            }
            return await actions.secretInsert(label: label, target: request.target, window: request.args?.window,
                                              pane: request.args?.pane)
        default:
            preconditionFailure("dispatchSecretCommand called for \(request.cmd.rawValue)")
        }
    }

    private func validLabel(_ request: ControlRequest) -> String? {
        guard let label = request.args?.label.trimmedOrNilValue,
              label.count <= SecretPolicy.maxLabelLength, !containsControlCharacters(label) else { return nil }
        return label
    }

    private func labelError(_ request: ControlRequest, verb: String) -> String {
        guard let label = request.args?.label.trimmedOrNilValue else { return "\(verb) requires a label" }
        if label.count > SecretPolicy.maxLabelLength {
            return "label too long (max \(SecretPolicy.maxLabelLength) characters)"
        }
        return "label must not contain control characters"
    }
}
