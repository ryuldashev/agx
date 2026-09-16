import AppKit
import XCTest
@testable import agterm

/// The Add Secret… dialog is hand-built; the field kinds, focus order, and its rejection wording are what
/// keep a typed password out of a plain field and out of the keychain when it cannot be typed back.
@MainActor
final class SecretAddPromptTests: XCTestCase {
    func testValueFieldIsSecureAndLabelTakesFocusFirst() {
        let built = SecretAddPrompt.makeAlert()
        XCTAssertTrue(built.value is NSSecureTextField)
        XCTAssertTrue(built.alert.window.initialFirstResponder === built.label)
        XCTAssertTrue(built.label.nextKeyView === built.value, "Tab moves from the label into the secret")
        XCTAssertEqual(built.alert.buttons.map(\.title), ["Save", "Cancel"])
    }

    func testProblemsFollowSecretPolicy() {
        XCTAssertEqual(SecretAddPrompt.problem(label: "", value: "x"), "Enter a label.")
        XCTAssertEqual(SecretAddPrompt.problem(label: "root", value: ""), "Enter the secret.")
        XCTAssertEqual(SecretAddPrompt.problem(label: "a\tb", value: "x"), "label must not contain control characters")
        XCTAssertEqual(SecretAddPrompt.problem(label: "root", value: "a\nb"), "value must not contain control characters")
        XCTAssertNil(SecretAddPrompt.problem(label: "root", value: "Tr0ub4dor&3"))
    }
}
