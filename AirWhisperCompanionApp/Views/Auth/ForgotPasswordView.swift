import SwiftUI

/// Forgot Password flow entry screen.
/// Port of `ForgotPasswordViewController` — exact visual and behavioral parity.
struct ForgotPasswordView: View {

    let onPasswordResetCompleted: () -> Void

    @State private var email = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isLoading = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Design.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // "Account Recovery" title
                    Text("Account Recovery")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)

                    // "Forgot Password" subtitle
                    Text("Forgot Password")
                        .font(.system(size: 25, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    // Description
                    Text("Enter your email address associated with your account")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.contentMargin)
                        .padding(.top, 16)

                    // Email field
                    AuthTextField(
                        placeholder: "Email address",
                        text: $email,
                        keyboardType: .emailAddress,
                        fontSize: 16
                    )
                    .padding(.horizontal, Design.contentMargin)
                    .padding(.top, 32)

                    // Send OTP button
                    PrimaryButton(
                        title: "Send OTP",
                        height: 52,
                        isEnabled: !isLoading
                    ) {
                        sendOTP()
                    }
                    .padding(.horizontal, Design.contentMargin)
                    .padding(.top, 24)

                    Spacer()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ForgotPasswordRoute.self) { route in
                switch route {
                case .otp(let email):
                    ForgotPasswordOTPView(email: email) { resetToken in
                        navigationPath.append(ForgotPasswordRoute.newPassword(resetToken))
                    }
                case .newPassword(let resetToken):
                    SetNewPasswordView(resetToken: resetToken) {
                        onPasswordResetCompleted()
                    }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func sendOTP() {
        guard email.contains("@") else {
            alertTitle = "Invalid Email"
            alertMessage = "Please enter a valid email address."
            showAlert = true
            return
        }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await AuthService.forgotPassword(email: email)
                await MainActor.run {
                    navigationPath.append(ForgotPasswordRoute.otp(email))
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

private enum ForgotPasswordRoute: Hashable {
    case otp(String)
    case newPassword(String)
}

#Preview {
    ForgotPasswordView(onPasswordResetCompleted: {})
}