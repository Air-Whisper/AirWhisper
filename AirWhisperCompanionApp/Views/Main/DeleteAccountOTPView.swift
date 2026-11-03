import SwiftUI
import UIKit
import GoogleSignIn
import os

private let deleteAccountOTPLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AirWhisper",
    category: "DeleteAccountOTP"
)

/// Full-screen, red-accented account deletion confirmation.
struct DeleteAccountOTPView: View {

    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var appState: AppState

    let email: String

    @State private var digits = Array(repeating: "", count: 6)
    @State private var focusedIndex: Int? = 0
    @State private var isVerifying = false
    @State private var isResendEnabled = true
    @State private var resendCountdown = 0
    @State private var resendTimer: Timer?
    @State private var isAlertPresented = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var displayEmail: String {
        email.isEmpty ? "your registered address" : email
    }

    private var isVerifyEnabled: Bool {
        digits.allSatisfy { !$0.isEmpty } && !isVerifying
    }

    private var resendTitle: String {
        guard resendCountdown > 0 else { return "Didn't receive code? Resend" }
        let minutes = resendCountdown / 60
        let seconds = resendCountdown % 60
        let time = String(format: "%02d : %02d", minutes, seconds)
        return "Didn't receive code?\nResend - \(time)"
    }

    var body: some View {
        ZStack {
            Design.background.ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }

            VStack(spacing: 0) {
                Text("Confirm account deletion")
                    .font(.system(size: 25, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)

                Text("Enter the 6-digit code sent to\n\(displayEmail)")
                    .font(.system(size: 16))
                    .foregroundStyle(Design.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                DeleteAccountOTPFieldStack(
                    digits: $digits,
                    focusedIndex: $focusedIndex,
                    onSubmit: verifyTapped
                )
                .frame(height: 60)
                .padding(.horizontal, 24)
                .padding(.top, 50)

                Button(action: verifyTapped) {
                    ZStack {
                        if isVerifying {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Delete My Account")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Design.destructiveRed.opacity(isVerifyEnabled ? 1 : 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!isVerifyEnabled)
                .accessibilityLabel("Delete My Account")
                .padding(.horizontal, 24)
                .padding(.top, 40)

                Button(action: resendTapped) {
                    resendButtonLabel
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!isResendEnabled)
                .frame(height: 30)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer(minLength: 0)
            }
        }
        .alert(alertTitle, isPresented: $isAlertPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            resendTimer?.invalidate()
            resendTimer = nil
        }
    }

    private var resendButtonLabel: Text {
        if resendCountdown > 0 {
            let time = String(format: "%02d : %02d", resendCountdown / 60, resendCountdown % 60)
            return Text("Didn't receive code?\n")
                .foregroundColor(.secondary)
                + Text("Resend")
                .foregroundColor(Color(uiColor: .systemRed))
                + Text(" - \(time)")
                .foregroundColor(.secondary)
        }
        return Text("Didn't receive code? ")
            .foregroundColor(.secondary)
            + Text("Resend")
            .foregroundColor(Color(uiColor: .systemRed))
    }

    private func verifyTapped() {
        let code = digits.joined()
        guard code.count == 6, !isVerifying else { return }
        isVerifying = true

        Task {
            do {
                try await AuthService.deleteAccount(code: code)
                await disconnectGoogleSessionIfNeeded()
                await MainActor.run {
                    dataManager.clearUser(deleteCloudData: true, watchSignal: .accountDeleted)
                    UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    appState.route = .onboarding
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    showAlert(title: "Deletion Failed", message: error.localizedDescription)
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
                try await AuthService.requestDeleteOTP()
                await MainActor.run {
                    showAlert(title: "Code Resent", message: "A new code has been sent to your registered email.")
                    startResendTimer()
                }
            } catch {
                await MainActor.run {
                    isResendEnabled = true
                    showAlert(title: "Resend Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func startResendTimer() {
        resendCountdown = 60
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
            Task { @MainActor in
                resendCountdown -= 1
                if resendCountdown <= 0 {
                    timer.invalidate()
                    resendTimer = nil
                    isResendEnabled = true
                }
            }
        }
    }

    @MainActor
    private func disconnectGoogleSessionIfNeeded() async {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.disconnect { error in
                if let error {
                    deleteAccountOTPLogger.error("Google disconnect failed during account deletion: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isAlertPresented = true
    }
}

/// UIKit-backed six-field OTP input matching the red deletion OTP fields.
private struct DeleteAccountOTPFieldStack: UIViewRepresentable {

    @Binding var digits: [String]
    @Binding var focusedIndex: Int?
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12

        for index in 0..<6 {
            let field = UITextField()
            field.tag = index
            field.delegate = context.coordinator
            field.borderStyle = .roundedRect
            field.textAlignment = .center
            field.font = UIFontMetrics.default.scaledFont(
                for: UIFont.systemFont(ofSize: 22, weight: .medium)
            )
            field.adjustsFontForContentSizeCategory = true
            field.keyboardType = .numberPad
            field.layer.cornerRadius = 12
            field.layer.borderWidth = 1
            field.layer.borderColor = UIColor.systemRed.cgColor
            field.backgroundColor = .systemBackground
            field.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidChange(_:)), for: .editingChanged)
            field.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidBeginEditing(_:)), for: .editingDidBegin)
            field.addTarget(context.coordinator, action: #selector(Coordinator.textFieldDidEndEditing(_:)), for: .editingDidEnd)
            context.coordinator.textFields.append(field)
            stack.addArrangedSubview(field)
            field.heightAnchor.constraint(equalToConstant: 60).isActive = true
        }

        for (index, field) in context.coordinator.textFields.enumerated() {
            field.text = digits[index]
        }

        let coordinator = context.coordinator
        Task { @MainActor [weak coordinator] in
            await Task.yield()
            coordinator?.textFields.first?.becomeFirstResponder()
        }
        return stack
    }

    func updateUIView(_ uiView: UIStackView, context: Context) {
        for (index, field) in context.coordinator.textFields.enumerated() {
            if field.text != digits[index] {
                field.text = digits[index]
            }
        }
        if let focusedIndex,
           focusedIndex >= 0,
           focusedIndex < context.coordinator.textFields.count {
            let field = context.coordinator.textFields[focusedIndex]
            if !field.isFirstResponder {
                field.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let parent: DeleteAccountOTPFieldStack
        var textFields: [UITextField] = []

        init(_ parent: DeleteAccountOTPFieldStack) {
            self.parent = parent
        }

        @objc func textFieldDidChange(_ textField: UITextField) {
            let enteredText = textField.text ?? ""
            if enteredText.count > 1 {
                textField.text = String(enteredText.prefix(1))
            }

            let finalText = textField.text ?? ""
            let index = textFields.firstIndex(of: textField) ?? 0
            parent.digits[index] = finalText
            if finalText.count == 1 {
                if index < textFields.count - 1 {
                    textFields[index + 1].becomeFirstResponder()
                } else {
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
            if string.isEmpty && (textField.text?.isEmpty ?? true) {
                let index = textFields.firstIndex(of: textField) ?? 0
                if index > 0 {
                    let previousField = textFields[index - 1]
                    previousField.becomeFirstResponder()
                    previousField.text = ""
                    parent.digits[index - 1] = ""
                }
                return false
            }
            return true
        }

        @objc func textFieldDidBeginEditing(_ textField: UITextField) {
            textField.layer.borderColor = UIColor.systemRed.cgColor
            textField.layer.borderWidth = 2
            parent.focusedIndex = textFields.firstIndex(of: textField) ?? 0
        }

        @objc func textFieldDidEndEditing(_ textField: UITextField) {
            textField.layer.borderColor = UIColor.systemRed.cgColor
            textField.layer.borderWidth = 1
        }
    }
}
