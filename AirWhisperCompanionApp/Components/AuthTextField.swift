import SwiftUI
import UIKit

/// Standard authentication text field.
///
/// Visual port of `UITextField+Style.applyStandardAuthStyle()`:
/// - 12pt corner radius, 1pt border in systemGray4, 16pt left/right padding
/// - Focus state: systemBlue border + 2pt width
/// - Optional password visibility toggle (eye / eye.slash)
struct AuthTextField: View {

    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var fontSize: CGFloat = 14

    @FocusState private var isFocused: Bool
    @State private var isPasswordVisible = false

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .focused($isFocused)
                        .keyboardType(keyboardType)
                } else {
                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .keyboardType(keyboardType)
                }
            }
            .font(.system(size: fontSize))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(isSecure)

            if isSecure {
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show or hide password")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Design.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFocused ? Design.brandBlue : Color(uiColor: .systemGray4),
                        lineWidth: isFocused ? 2 : 1)
        }
        .accessibilityLabel(placeholder)
    }
}
