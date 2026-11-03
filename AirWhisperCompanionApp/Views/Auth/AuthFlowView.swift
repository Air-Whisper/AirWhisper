import SwiftUI
import UIKit

/// Auth flow container: replaces `MainAuthViewController`.
/// Shows either Create Account or Sign In screen and manages modal presentations.
struct AuthFlowView: View {

    @EnvironmentObject private var appState: AppState

    // MARK: - Internal auth screen state
    private enum AuthScreen: Equatable {
        case createAccount
        case signIn
    }
    @State private var screen: AuthScreen = .createAccount

    // MARK: - Modal presentation state
    @State private var otpMode: OtpFlowMode?
    @State private var showForgotPassword = false
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Design.background
                    .ignoresSafeArea()

                Group {
                    switch screen {
                    case .createAccount:
                        CreateAccountView(
                            switchToSignIn: { screen = .signIn },
                            onRequestOTP: { mode in otpMode = mode },
                            onWatchOnboardingRequired: { navigateToWatchOnboarding() }
                        )

                    case .signIn:
                        SignInView(
                            switchToCreateAccount: { screen = .createAccount },
                            onForgotPassword: { showForgotPassword = true },
                            onRequestOTP: { mode in otpMode = mode },
                            onWatchOnboardingRequired: { navigateToWatchOnboarding() }
                        )
                    }
                }
                .animation(nil, value: screen) // no animation on swap (matches UIKit behavior)
            }
            .navigationBarHidden(true)
        }
        // OTP verification sheet (pageSheet — no explicit detents, matching UIKit .pageSheet)
        .sheet(item: $otpMode) { mode in
            OTPVerificationView(mode: mode) {
                // Dismiss sheet first, then trigger watch onboarding (order matters)
                otpMode = nil
                navigateToWatchOnboarding()
            }
        }
        // Forgot password sheet (wrapped in NavigationStack like UINavigationController; .large detent)
        .sheet(isPresented: $showForgotPassword) {
            NavigationStack {
                ForgotPasswordView(onPasswordResetCompleted: {
                    showForgotPassword = false
                    showToast("Password has been changed successfully")
                })
            }
            .presentationDetents([.large])
        }
        // Toast overlay
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                ToastView(message: message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                    .padding(.horizontal, 32)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
    }

    // MARK: - Navigation helpers (ported from MainAuthViewController)

    private func navigateToWatchOnboarding() {
        appState.route = .watchPairing
    }

    /// Port of `MainAuthViewController.showToast(message:duration:)`.
    /// Visual fidelity: dark rounded label, centered, bottom-anchored to safe area −24pt,
    /// horizontal insets 32pt, fade-in 0.3s, hold `duration`, fade-out 0.4s.
    private func showToast(_ message: String, duration: TimeInterval = 3.0) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.7) * 1_000_000_000))
            // Fade out animation handled by .animation on toastMessage change
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.4)) {
                    toastMessage = nil
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AuthFlowView()
        .environmentObject(AppState())
}