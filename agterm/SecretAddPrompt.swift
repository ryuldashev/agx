import AppKit
import agtermCore

/// The palette's Add Secret… dialog: a label and a secure value field in an `NSAlert`, validated by the same
/// `SecretPolicy` as `secret.add`. The value never leaves the field except into the keychain.
@MainActor
enum SecretAddPrompt {
    struct Built {
        let alert: NSAlert
        let label: NSTextField
        let value: NSSecureTextField
        let error: NSTextField
    }

    static let fieldWidth: CGFloat = 220

    /// Run the dialog as a sheet on `window` — app-modal would open on another Space when the terminal is
    /// fullscreen — until Save stores a valid secret or Cancel; `completion` gets the stored label or nil.
    /// A rejected entry re-presents the same sheet with the reason under the fields, values kept.
    static func present(in window: NSWindow?, store: @escaping (String, String) throws -> Void,
                        completion: @escaping (String?) -> Void) {
        run(makeAlert(), in: window, store: store, completion: completion)
    }

    private static func run(_ built: Built, in window: NSWindow?, store: @escaping (String, String) throws -> Void,
                            completion: @escaping (String?) -> Void) {
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return completion(nil) }
            let label = built.label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = built.value.stringValue
            if let problem = problem(label: label, value: value) {
                built.error.stringValue = problem
            } else {
                do {
                    try store(label, value)
                    return completion(label)
                } catch {
                    built.error.stringValue = "keychain: \(error)"
                }
            }
            DispatchQueue.main.async { run(built, in: window, store: store, completion: completion) }
        }
        if let window {
            built.alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(built.alert.runModal())
        }
    }

    static func problem(label: String, value: String) -> String? {
        if label.isEmpty { return "Enter a label." }
        if let error = SecretPolicy.labelError(label) { return error }
        if value.isEmpty { return "Enter the secret." }
        return SecretPolicy.valueError(value)
    }

    /// The alert and its fields, split out so a hosted test can check them without running a modal. The
    /// fields carry a width constraint because the stack otherwise shrinks them to their placeholder.
    static func makeAlert() -> Built {
        let label = NSTextField(string: "")
        label.placeholderString = "Label, e.g. db-root"
        label.setAccessibilityIdentifier("secret-add-label")
        let value = NSSecureTextField(string: "")
        value.placeholderString = "Secret"
        value.setAccessibilityIdentifier("secret-add-value")
        label.nextKeyView = value
        value.nextKeyView = label
        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        error.textColor = .systemRed
        error.preferredMaxLayoutWidth = fieldWidth
        error.setAccessibilityIdentifier("secret-add-error")
        for field in [label, value, error] {
            field.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        }

        let stack = NSStackView(views: [label, value, error])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        let container = NSView(frame: stack.frame)
        container.addSubview(stack)

        let alert = NSAlert()
        alert.messageText = "Add Secret"
        alert.informativeText = "Stored in your login keychain. Insert Secret… types it into the terminal."
        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.setAccessibilityIdentifier("secret-add-save")
        alert.window.initialFirstResponder = label
        alert.layout()
        AlertAccessoryLayout.indent(stack, container: container, reference: label, in: alert)
        return Built(alert: alert, label: label, value: value, error: error)
    }
}
