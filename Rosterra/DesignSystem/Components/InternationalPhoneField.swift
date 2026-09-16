import SwiftUI
import PhoneNumberKitUI

/// Country-aware phone entry with Australia selected by default.
struct InternationalPhoneField: UIViewRepresentable {
    @Binding var text: String

    final class AustralianPhoneNumberTextField: PhoneNumberTextField {
        override var defaultRegion: String {
            get { "AU" }
            set { }
        }
    }

    final class Coordinator: NSObject {
        let parent: InternationalPhoneField

        init(parent: InternationalPhoneField) {
            self.parent = parent
        }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> AustralianPhoneNumberTextField {
        let field = AustralianPhoneNumberTextField()
        field.withFlag = true
        field.withPrefix = true
        field.withExamplePlaceholder = true
        field.withDefaultPickerUI = true
        field.keyboardType = .phonePad
        field.textContentType = .telephoneNumber
        field.font = .preferredFont(forTextStyle: .body)
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            field.text = "+61 "
            DispatchQueue.main.async { text = field.text ?? "+61 " }
        } else {
            field.text = text
        }
        return field
    }

    func updateUIView(_ field: AustralianPhoneNumberTextField, context: Context) {
        if field.text != text {
            field.text = text
        }
    }
}
