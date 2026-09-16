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

    /// Run the dialog until Save stores a valid secret or Cancel. Returns the stored label, nil on cancel.
    /// A rejected entry keeps the dialog up with the reason under the fields, so a typo costs one retry.
    static func present(store: (String, String) throws -> Void) -> String? {
        let built = makeAlert()
        while built.alert.runModal() == .alertFirstButtonReturn {
            let label = built.label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = built.value.stringValue
            if let problem = problem(label: label, value: value) {
                built.error.stringValue = problem
                continue
            }
            do {
                try store(label, value)
                return label
            } catch {
                built.error.stringValue = "keychain: \(error)"
            }
        }
        return nil
    }

    static func problem(label: String, value: String) -> String? {
        if label.isEmpty { return "Enter a label." }
        if let error = SecretPolicy.labelError(label) { return error }
        if value.isEmpty { return "Enter the secret." }
        return SecretPolicy.valueError(value)
    }

    /// The alert and its fields, split out so a hosted test can check them without running a modal.
    static func makeAlert() -> Built {
        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        label.placeholderString = "Label, e.g. db-root"
        label.setAccessibilityIdentifier("secret-add-label")
        let value = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        value.placeholderString = "Secret"
        value.setAccessibilityIdentifier("secret-add-value")
        label.nextKeyView = value
        value.nextKeyView = label
        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        error.textColor = .systemRed
        error.preferredMaxLayoutWidth = 260
        error.setAccessibilityIdentifier("secret-add-error")

        let stack = NSStackView(views: [label, value, error])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 24 + 6 + 24 + 6 + 32)
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
