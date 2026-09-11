import Foundation

extension ControlDispatcher {
    /// Validates `session.failure` host-free: the error type and message are text without control
    /// characters, the transcript path (when given) is absolute. What to do about it needs the session's
    /// memory and the settings, so the decision is app-side.
    func dispatchFailureCommand(_ request: ControlRequest) -> ControlResponse {
        let args = request.args
        guard let error = args?.error.trimmedOrNilValue else {
            return ControlResponse(ok: false, error: "session.failure requires an error type (rate_limit, server_error, …)")
        }
        guard !containsControlCharacters(error), !error.contains(" ") else {
            return ControlResponse(ok: false, error: "error type must be a single token")
        }
        let message = args?.message.trimmedOrNilValue ?? ""
        if let transcript = args?.transcript.trimmedOrNilValue {
            guard !containsControlCharacters(transcript) else {
                return ControlResponse(ok: false, error: "transcript path must not contain control characters")
            }
            guard transcript.hasPrefix("/") else {
                return ControlResponse(ok: false, error: "transcript path must be absolute: \(transcript)")
            }
        }
        return actions.reportFailure(request.target, options: ControlFailureOptions(
            window: args?.window, error: error, message: TerminalText.sanitized(message),
            transcript: args?.transcript.trimmedOrNilValue, forceHandoff: args?.handoff == true))
    }
}
