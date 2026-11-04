import SwiftUI
import UIKit

/// OTP flow mode — must match the enum name and cases expected by `AuthFlowView`.
enum OtpFlowMode: Equatable, Identifiable {
    case emailVerification(email: String)

    var id: String {
        switch self {
        case .emailVerification(let email): return email
        }
    }
}

/// Six digit verification with the original controls and 60 second resend countdown.
struct OTPVerificationView: View {

    // MARK: - Input
    let mode: OtpFlowMode
    let onVerified: () -> Void

    // MARK: - Derived
    private var email: String {
        if case .emailVerification(let e) = mode { return e }
        return ""
    }

    // MARK: - State
    @State private var digits: [String] = Array(repeating: "", count: 6)
    @State private var focusedIndex: Int? = 0
    @State private var isSubmitting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showResendAlert = false
    @State private var resendAlertMessage = ""
    @State private var resendCountdown = 0
    @State private var resendTimer: Timer?
    @State private var isResendEnabled = true

    private var isVerifyEnabled: Bool {
        digits.allSatisfy { !$0.isEmpty } && !isSubmitting
    }

    private var resendButtonTitle: String {
        if resendCountdown > 0 {
            let minutes = resendCountdown / 60
            let seconds = resendCountdown % 60
            let timeStr = String(format: "%02d : %02d", minutes, seconds)
            return "Didn't receive code?\nResend - \(timeStr)"
        } else {
            return "Didn't receive code? Resend"
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Design.background.ignoresSafeArea()

                // Tap to dismiss keyboard (matches UITapGestureRecognizer on view)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }

                VStack(spacing: 0) {
                    // Title
                    Text("We just sent an email")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                        .padding(.bottom, 12)

                    // Subtitle
                    Text("Enter the security code we sent to\n\(email)")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 32)

                    // 6-digit OTP fields (UIKit-backed for exact parity)
                    OTPFieldStack(
                        digits: $digits,
                        focusedIndex: $focusedIndex,
                        onSubmit: { verifyTapped() },
                        onDigitChange: { _, _ in }
                    )
                    .frame(height: 60)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)

                    // Verify button
                    PrimaryButton(
                        title: "Verify",
                        style: .filled,
                        height: 52,
                        isEnabled: isVerifyEnabled
                    ) {
                        verifyTapped()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // Resend button
                    TextLinkButton(
                        title: resendButtonTitle,
                        accentRange: "Resend",
                        fontSize: 16,
                        alignment: .center
                    ) {
                        resendTapped()
                    }
                    .disabled(!isResendEnabled)
                    .opacity(isResendEnabled ? 1.0 : 0.5)
                    .frame(height: 30)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

                    Spacer(minLength: 0)
                }
            }
        }
        .alert("Verification Failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Code Resent", isPresented: $showResendAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resendAlertMessage)
        }
        .onAppear {
            // Timer cleanup handled by onDisappear; no extra work needed here.
        }
        .onDisappear {
            resendTimer?.invalidate()
            resendTimer = nil
        }
    }

    // MARK: - Actions

    private func verifyTapped() {
        guard !isSubmitting else { return }
        let code = digits.joined()
        guard code.count == 6 else { return }
        isSubmitting = true

        Task {
            do {
                let response = try await AuthService.verifyEmail(email: email, code: code)
                await MainActor.run {
                    StorageManager.shared.saveSession(
                        accessToken: response.accessToken,
                        refreshToken: response.refreshToken
                    )
                    StorageManager.shared.setAppleIDSession(false)
                    DataManager.shared.setupNewUser(
                        name: response.user.name,
                        email: response.user.email
                    )
                    isSubmitting = false
                    onVerified() // parent dismisses sheet, then navigates to watch onboarding
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                    // Clear all fields and focus first
                    digits = Array(repeating: "", count: 6)
                    focusedIndex = 0
                }
            }
        }
    }

    private func resendTapped() {
        guard isResendEnabled else { return }
        isResendEnabled = false

        Task {
            do {
                try await AuthService.resendVerification(email: email)
                await MainActor.run {
                    resendAlertMessage = "A new code has been sent to \(email)."
                    showResendAlert = true
                    startResendTimer()
                }
            } catch {
                await MainActor.run {
                    isResendEnabled = true
                    resendAlertMessage = error.localizedDescription
                    showResendAlert = true
                }
            }
        }
    }

    // MARK: - Resend Timer

    private func startResendTimer() {
        resendCountdown = 60
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            Task { @MainActor in
                self.resendCountdown -= 1
                if self.resendCountdown <= 0 {
                    timer.invalidate()
                    self.resendTimer = nil
                    self.isResendEnabled = true
                }
                // resendCountdown is @State; SwiftUI will re-render the button title automatically.
            }
        }
    }
}

// MARK: - UIKit-backed OTP Field Stack

/// `UIViewRepresentable` wrapping a `UIStackView` with six `UITextField`s.
/// Preserves the original OTP input behavior:
/// - Single-character limit per field
/// - Auto-advance on entry, auto-submit on 6th digit
/// - Backspace on empty field moves focus back and clears previous
/// - Focus ring (border width 2) on active field
/// - Dynamic Type scaling via `UIFontMetrics`
struct OTPFieldStack: UIViewRepresentable {

    @Binding var digits: [String]
    @Binding var focusedIndex: Int?
    let onSubmit: () -> Void
    let onDigitChange: (Int, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        stack.alignment = .fill

        let brandBlueUIColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)
        let scaledFont = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 22, weight: .medium)
        )

        for i in 0..<6 {
            let field = UITextField()
            field.tag = i
            field.delegate = context.coordinator
            field.textAlignment = .center
            field.font = scaledFont
            field.adjustsFontForContentSizeCategory = true
            field.keyboardType = .numberPad
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1
            field.layer.borderColor = brandBlueUIColor.cgColor
            field.backgroundColor = .systemBackground
            field.textContentType = .oneTimeCode

            // Targets for text change / focus ring
            field.addTarget(
                context.coordinator,
                action: #selector(Coordinator.textFieldDidChange(_:)),
                for: .editingChanged
            )
            field.addTarget(
                context.coordinator,
                action: #selector(Coordinator.textFieldDidBeginEditing(_:)),
                for: .editingDidBegin
            )
            field.addTarget(
                context.coordinator,
                action: #selector(Coordinator.textFieldDidEndEditing(_:)),
                for: .editingDidEnd
            )

            context.coordinator.textFields.append(field)
            stack.addArrangedSubview(field)

            // Height constraint (60 pt)
            field.heightAnchor.constraint(equalToConstant: 60).isActive = true
        }

        // Set initial text from digits binding
        for (i, field) in context.coordinator.textFields.enumerated() {
            field.text = digits[i]
        }

        // Focus first field on appear
        let coordinator = context.coordinator
        Task { @MainActor [weak coordinator] in
            await Task.yield()
            coordinator?.textFields.first?.becomeFirstResponder()
        }

        return stack
    }

    func updateUIView(_ uiView: UIStackView, context: Context) {
        context.coordinator.parent = self

        // Sync text fields with digits binding
        for (i, field) in context.coordinator.textFields.enumerated() {
            if field.text != digits[i] {
                field.text = digits[i]
            }
        }

        // Sync focus from SwiftUI (if ever driven externally)
        if let targetIndex = focusedIndex,
           targetIndex >= 0, targetIndex < context.coordinator.textFields.count {
            let targetField = context.coordinator.textFields[targetIndex]
            if !targetField.isFirstResponder {
                targetField.becomeFirstResponder()
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OTPFieldStack
        var textFields: [UITextField] = []

        init(_ parent: OTPFieldStack) {
            self.parent = parent
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            let text = textField.text ?? ""
            let index = textFields.firstIndex(of: textField) ?? 0

            // Restrict to single character
            if text.count > 1 {
                textField.text = String(text.prefix(1))
            }

            let finalText = textField.text ?? ""
            parent.digits[index] = finalText
            parent.onDigitChange(index, finalText)

            // Auto-advance or auto-submit
            if finalText.count == 1 {
                if index < textFields.count - 1 {
                    parent.focusedIndex = index + 1
                    textFields[index + 1].becomeFirstResponder()
                } else {
                    parent.focusedIndex = nil
                    textField.resignFirstResponder()
                    parent.onSubmit()
                }
            }
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Backspace on empty field → move back, clear previous
            if string.isEmpty && (textField.text?.isEmpty ?? true) {
                let index = textFields.firstIndex(of: textField) ?? 0
                if index > 0 {
                    let prevField = textFields[index - 1]
                    parent.focusedIndex = index - 1
                    prevField.becomeFirstResponder()
                    prevField.text = ""
                    parent.digits[index - 1] = ""
                    parent.onDigitChange(index - 1, "")
                }
                return false // suppress the deletion (we already cleared)
            }
            return true
        }

        @objc func textFieldDidBeginEditing(_ textField: UITextField) {
            let brandBlueUIColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)
            textField.layer.borderColor = brandBlueUIColor.cgColor
            textField.layer.borderWidth = 2

            let index = textFields.firstIndex(of: textField) ?? 0
            parent.focusedIndex = index
        }

        @objc func textFieldDidEndEditing(_ textField: UITextField) {
            let brandBlueUIColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)
            textField.layer.borderColor = brandBlueUIColor.cgColor
            textField.layer.borderWidth = 1

            let index = textFields.firstIndex(of: textField) ?? 0
            if parent.focusedIndex == index {
                parent.focusedIndex = nil
            }
        }
    }
}

// MARK: - Preview

#Preview {
    OTPVerificationView(mode: .emailVerification(email: "test@example.com")) {
        print("Verified!")
    }
    .environmentObject(AppState())
}
