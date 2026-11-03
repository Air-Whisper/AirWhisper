import SwiftUI

/// Set new password screen for password reset flow.
/// Port of `SetNewPasswordViewController` — exact visual and behavioral parity.
struct SetNewPasswordView: View {

    let resetToken: String
    let onCompleted: () -> Void

    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

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

                // "Reset Password" subtitle
                Text("Reset Password")
                    .font(.system(size: 25, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                // Description
                Text("The new password must be different from the previous password")
                    .font(.system(size: 16))
                    .foregroundStyle(Design.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.contentMargin)
                    .padding(.top, 16)

                // New password field
                AuthTextField(
                    placeholder: "Enter your new password",
                    text: $newPassword,
                    isSecure: true,
                    fontSize: 16
                )
                .padding(.horizontal, Design.contentMargin)
                .padding(.top, 32)

                // Confirm button
                PrimaryButton(
                    title: "Confirm",
                    height: 52,
                    isEnabled: !isLoading
                ) {
                    confirmPassword()
                }
                .padding(.horizontal, Design.contentMargin)
                .padding(.top, 24)

                Spacer()
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func confirmPassword() {
        // Validation: at least 8 chars, contains letter, digit, and special character
        let hasLetter = newPassword.rangeOfCharacter(from: .letters) != nil
        let hasDigit = newPassword.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecial = newPassword.rangeOfCharacter(from: .alphanumerics.inverted) != nil
        let isLongEnough = newPassword.count >= 8

        guard isLongEnough && hasLetter && hasDigit && hasSpecial else {
            alertTitle = "Weak Password"
            alertMessage = "Password must be at least 8 characters and include a letter, a number, and a special character."
            showAlert = true
            return
        }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await AuthService.resetPassword(resetToken: resetToken, newPassword: newPassword)
                await MainActor.run {
                    onCompleted()
                }
            } catch {
                await MainActor.run {
                    alertTitle = "Reset Failed"
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

#Preview {
    SetNewPasswordView(resetToken: "", onCompleted: {})
}