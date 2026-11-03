import SwiftUI
import UIKit

/// OTP verification screen for password reset.
/// Port of `ForgotPasswordOTPViewController` — exact visual and behavioral parity.
struct ForgotPasswordOTPView: View {

    let email: String
    let onResetTokenReceived: (String) -> Void

    @State private var otpDigits = Array(repeating: "", count: 6)
    @State private var focusedIndex: Int? = 0
    @State private var isVerifyLoading = false
    @State private var isResendLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var isVerifyEnabled: Bool {
        otpDigits.allSatisfy { !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            Design.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // "Account Recovery" title
                Text("Account Recovery")
                    .font(.system(size: 25, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 45)

                // "We just sent an email"
                Text("We just sent an email")
                    .font(.system(size: 25, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                // Subtitle with email
                Text("Enter the security code we sent to\n\(email)")
                    .font(.system(size: 16))
                    .foregroundStyle(Design.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.contentMargin)
                    .padding(.top, 16)

                // 6 OTP fields
                HStack(spacing: 12) {
                    ForEach(0..<6, id: \.self) { index in
                        OTPDigitField(
                            text: $otpDigits[index],
                            isFocused: focusedIndex == index,
                            onFocusChange: { isFocused in
                                if isFocused { focusedIndex = index }
                            },
                            onBackspaceWhenEmpty: {
                                handleBackspace(at: index)
                            },
                            onTextChange: { newText in
                                handleTextChange(at: index, newText: newText)
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)

                // Verify button
                PrimaryButton(
                    title: "Verify",
                    height: 52,
                    isEnabled: isVerifyEnabled && !isVerifyLoading
                ) {
                    verifyOTP()
                }
                .padding(.horizontal, Design.contentMargin)
                .padding(.top, 24)

                // Resend button
                TextLinkButton(
                    title: "Didn't receive code? Resend",
                    accentRange: "Resend",
                    fontSize: 14
                ) {
                    resendCode()
                }
                .frame(height: 30)
                .padding(.horizontal, Design.contentMargin)
                .padding(.top, 16)

                Spacer()
            }
        }
        .onAppear {
            // Focus first field on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedIndex = 0
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func handleTextChange(at index: Int, newText: String) {
        // Truncate to 1 character
        if newText.count > 1 {
            otpDigits[index] = String(newText.prefix(1))
        } else {
            otpDigits[index] = newText
        }

        // Auto-advance
        if newText.count == 1 && index < 5 {
            focusedIndex = index + 1
        }

        // Auto-submit on 6th digit
        if index == 5 && newText.count == 1 && isVerifyEnabled {
            verifyOTP()
        }
    }

    private func handleBackspace(at index: Int) {
        if index > 0 {
            otpDigits[index - 1] = ""
            focusedIndex = index - 1
        }
    }

    private func verifyOTP() {
        let code = otpDigits.joined()
        guard code.count == 6 else { return }

        isVerifyLoading = true
        Task {
            defer { isVerifyLoading = false }
            do {
                let resetToken = try await AuthService.verifyReset(email: email, code: code)
                await MainActor.run {
                    onResetTokenReceived(resetToken)
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Invalid Code"
                    alertMessage = error.localizedDescription
                    showAlert = true
                    // Clear fields and focus first
                    otpDigits = Array(repeating: "", count: 6)
                    focusedIndex = 0
                }
            }
        }
    }

    private func resendCode() {
        isResendLoading = true
        Task {
            defer { isResendLoading = false }
            do {
                try await AuthService.forgotPassword(email: email)
                await MainActor.run {
                    alertTitle = "Code Resent"
                    alertMessage = "A new code has been sent to \(email)."
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Error"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

/// Individual OTP digit field backed by UITextField for exact UIKit behavior (backspace on empty, focus handling).
private struct OTPDigitField: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Bool
    let onFocusChange: (Bool) -> Void
    let onBackspaceWhenEmpty: () -> Void
    let onTextChange: (String) -> Void

    func makeUIView(context: Context) -> OTPTextField {
        let field = OTPTextField()
        field.delegate = context.coordinator
        field.font = UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 22, weight: .medium))
        field.adjustsFontForContentSizeCategory = true
        field.textAlignment = .center
        field.keyboardType = .numberPad
        field.layer.borderColor = UIColor.lightGray.cgColor
        field.layer.borderWidth = 1
        field.layer.cornerRadius = 12
        field.backgroundColor = UIColor.systemBackground
        field.clipsToBounds = true
        field.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: OTPTextField, context: Context) {
        uiView.text = text
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        // Update border for focus state
        if isFocused {
            uiView.layer.borderColor = UIColor.systemBlue.cgColor
            uiView.layer.borderWidth = 2
        } else {
            uiView.layer.borderColor = UIColor.lightGray.cgColor
            uiView.layer.borderWidth = 1
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class OTPTextField: UITextField {
        // Override to allow backspace detection when empty
        override func deleteBackward() {
            if text?.isEmpty ?? true {
                // Notify delegate before calling super
                if let delegate = delegate as? OTPTextFieldDelegate {
                    delegate.otpTextFieldBackspaceOnEmpty(self)
                }
            }
            super.deleteBackward()
        }
    }

    protocol OTPTextFieldDelegate: UITextFieldDelegate {
        func otpTextFieldBackspaceOnEmpty(_ textField: OTPTextField)
    }

    final class Coordinator: NSObject, OTPTextFieldDelegate {
        let parent: OTPDigitField

        init(_ parent: OTPDigitField) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onFocusChange(false)
        }

        @objc func textDidChange(_ textField: UITextField) {
            let newText = textField.text ?? ""
            parent.onTextChange(newText)
            // Keep text in sync (truncate to 1 char)
            if newText.count > 1 {
                textField.text = String(newText.prefix(1))
            }
        }

        func otpTextFieldBackspaceOnEmpty(_ textField: OTPTextField) {
            parent.onBackspaceWhenEmpty()
        }
    }
}

#Preview {
    ForgotPasswordOTPView(email: "test@example.com") { _ in }
}