import SwiftUI
import UIKit
import AuthenticationServices
import GoogleSignIn

/// Sign In screen — faithful SwiftUI port of `SignInContentViewController`.
/// Layout, strings, colors, and behavior match the storyboard exactly.
struct SignInView: View {

    // MARK: - Callbacks (match AuthFlowView's call site exactly)

    let switchToCreateAccount: () -> Void
    let onForgotPassword: () -> Void
    let onRequestOTP: (OtpFlowMode) -> Void
    let onWatchOnboardingRequired: () -> Void

    // MARK: - State

    @State private var email = ""
    @State private var password = ""

    @State private var isEmailSignInLoading = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isAlertPresented = false

    @State private var showLocalStorageAlert = false

    // MARK: - Helpers

    private var googleLogoImage: UIImage? {
        UIImage(named: "google_logo")
    }

    private var presentingViewController: UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = keyWindow.rootViewController else { return nil }
        return topMost(of: rootVC)
    }

    private func topMost(of viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topMost(of: presented)
        }
        if let nav = viewController as? UINavigationController,
           let visible = nav.visibleViewController {
            return topMost(of: visible)
        }
        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMost(of: selected)
        }
        return viewController
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Logo
                Image("AirWhisperLogoLightmode")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 70)
                    .accessibilityHidden(true)

                // Title
                Text("Sign In")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Email field
                AuthTextField(
                    placeholder: "Email",
                    text: $email,
                    isSecure: false,
                    keyboardType: .emailAddress,
                    fontSize: 14
                )

                // Password field
                AuthTextField(
                    placeholder: "Password",
                    text: $password,
                    isSecure: true,
                    keyboardType: .default,
                    fontSize: 14
                )

                // Sign In button
                PrimaryButton(
                    title: isEmailSignInLoading ? "" : "Sign In",
                    style: .filled,
                    height: 50,
                    isEnabled: !isEmailSignInLoading && !email.isEmpty && !password.isEmpty,
                    action: signInTapped
                )
                .overlay {
                    if isEmailSignInLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }

                // Forgot Password
                TextLinkButton(
                    title: "Forgot Password?",
                    accentRange: "Forgot Password?",
                    fontSize: 14,
                    alignment: .center,
                    action: { onForgotPassword() }
                )

                // OR divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 1)
                    Text("OR")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: 1)
                }
                .frame(maxWidth: .infinity)

                // Google button
                Button(action: handleGoogleSignInTapped) {
                    HStack(spacing: 8) {
                        if let logo = googleLogoImage {
                            Image(uiImage: logo)
                                .resizable()
                                .renderingMode(.original)
                                .frame(width: 18, height: 18)
                        }
                        Text("  Continue with Google")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Design.neutralButton)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isGoogleLoading)
                .overlay {
                    if isGoogleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    }
                }
                .accessibilityLabel("Continue with Google")
                .accessibilityHint("Signs in using your Google account.")

                // Apple button
                Button(action: handleAppleIDSignInTapped) {
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white)
                        Text("  Sign in with Apple")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isAppleLoading)
                .overlay {
                    if isAppleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                }
                .accessibilityLabel("Continue with Apple")
                .accessibilityHint("Signs in using your Apple ID.")

                // Switch to Create Account
                TextLinkButton(
                    title: "Don't have an account? Create Account",
                    accentRange: "Create Account",
                    fontSize: 15,
                    alignment: .center,
                    action: { switchToCreateAccount() }
                )
            }
            .padding(.horizontal, Design.contentMargin)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Design.background)
        .alert(
            alertTitle,
            isPresented: $isAlertPresented,
            actions: {
                Button("OK", role: .cancel) { }
            },
            message: {
                Text(alertMessage)
            }
        )
        .alert(
            "Data Stored Locally",
            isPresented: $showLocalStorageAlert,
            actions: {
                Button("Got it") {
                    onWatchOnboardingRequired()
                }
            },
            message: {
                Text("Your AirWhisper data — phrases, contacts, settings, and history — will be saved on this device only. It will not be synced or backed up across other devices. To enable cross-device sync, sign in with Apple ID.")
            }
        )
    }

    // MARK: - Actions

    private func signInTapped() {
        guard !email.isEmpty else {
            presentAlert(title: "Missing Email", message: "Please enter your email address.")
            return
        }
        guard !password.isEmpty else {
            presentAlert(title: "Missing Password", message: "Please enter your password.")
            return
        }

        isEmailSignInLoading = true
        Task {
            defer {
                DispatchQueue.main.async { isEmailSignInLoading = false }
            }
            do {
                let response = try await AuthService.login(email: email, password: password)
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
                    showLocalStorageAlert = true
                }
            } catch AuthError.unverified(let message) {
                await MainActor.run {
                    presentAlert(title: "Account Unverified", message: message)
                }
            } catch {
                await MainActor.run {
                    presentAlert(title: "Sign In Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func handleGoogleSignInTapped() {
        guard let presentingVC = presentingViewController else {
            presentAlert(title: "Sign In Failed", message: "Unable to find presenting view controller.")
            return
        }

        isGoogleLoading = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC) { [weakSelf = self] result, error in
            // Note: weakSelf pattern needed because we're in a closure capturing self
            // We'll handle the result on the main thread
            DispatchQueue.main.async { [self] in
                self.isGoogleLoading = false

                if let error = error {
                    self.presentAlert(title: "Sign In Failed", message: error.localizedDescription)
                    return
                }
                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.presentAlert(title: "Sign In Failed", message: "Unable to retrieve Google credentials.")
                    return
                }

                self.isGoogleLoading = true
                Task {
                    defer { DispatchQueue.main.async { self.isGoogleLoading = false } }
                    do {
                        let response = try await AuthService.googleSignIn(idToken: idToken)
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
                            self.showLocalStorageAlert = true
                        }
                    } catch {
                        await MainActor.run {
                            self.presentAlert(title: "Sign In Failed", message: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    private func handleAppleIDSignInTapped() {
        isAppleLoading = true
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = SignInAppleSignInCoordinator.shared
        controller.presentationContextProvider = SignInAppleSignInCoordinator.shared
        SignInAppleSignInCoordinator.shared.beginSignIn(
            onSuccess: { [weak self] identityToken, authorizationCode, fullName, appleUserIdentifier in
                guard let self = self else { return }
                Task {
                    do {
                        let response = try await AuthService.appleSignIn(
                            identityToken: identityToken,
                            authorizationCode: authorizationCode,
                            fullName: fullName
                        )
                        await MainActor.run {
                            StorageManager.shared.saveSession(
                                accessToken: response.accessToken,
                                refreshToken: response.refreshToken
                            )
                            StorageManager.shared.setAppleIDSession(true)
                            DataManager.shared.setupNewUser(
                                name: response.user.name,
                                email: response.user.email,
                                appleUserIdentifier: appleUserIdentifier
                            )
                            self.isAppleLoading = false
                            self.onWatchOnboardingRequired()
                        }
                    } catch {
                        await MainActor.run {
                            self.isAppleLoading = false
                            self.presentAlert(title: "Sign In Failed", message: error.localizedDescription)
                        }
                    }
                }
            },
            onFailure: { [weak self] error in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isAppleLoading = false
                    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                        return
                    }
                    self.presentAlert(title: "Sign In Failed", message: error.localizedDescription)
                }
            }
        )
        controller.performRequests()
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isAlertPresented = true
    }
}

// MARK: - Apple Sign-In Coordinator

/// Dedicated coordinator for Apple Sign-In to avoid colliding with the
/// existing `SignInContentViewController` delegate extensions.
final class SignInAppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    static let shared = SignInAppleSignInCoordinator()

    private var onSuccess: ((String, String, String?, String) -> Void)?
    private var onFailure: ((Error) -> Void)?

    private override init() { super.init() }

    func beginSignIn(
        onSuccess: @escaping (String, String, String?, String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.onSuccess = onSuccess
        self.onFailure = onFailure
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            onFailure?(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to retrieve Apple credentials."]))
            return
        }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            onFailure?(NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to retrieve Apple credentials."]))
            return
        }

        let fullName = formattedFullName(from: credential.fullName)
        let appleUserIdentifier = credential.user

        onSuccess?(identityToken, authorizationCode, fullName, appleUserIdentifier)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        onFailure?(error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return keyWindow
    }

    private func formattedFullName(from components: PersonNameComponents?) -> String? {
        guard let components = components else { return nil }
        let name = PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// MARK: - Preview

#Preview {
    SignInView(
        switchToCreateAccount: { print("Switch to Create Account") },
        onForgotPassword: { print("Forgot Password") },
        onRequestOTP: { _ in print("Request OTP") },
        onWatchOnboardingRequired: { print("Watch Onboarding Required") }
    )
}