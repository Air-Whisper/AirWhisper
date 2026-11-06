import SwiftUI
import UIKit
import AuthenticationServices
import GoogleSignIn

/// Create Account screen with the legacy validation and sign-in options.
///
/// Parity notes (from the original):
/// - Create button is disabled + 0.45 alpha until the ToS checkbox is accepted.
/// - Apple sign-in sets an Apple-ID session (iCloud sync); email/Google show
///   the "Data Stored Locally" notice before continuing.
struct CreateAccountView: View {

    let switchToSignIn: () -> Void
    let onRequestOTP: (OtpFlowMode) -> Void
    let onWatchOnboardingRequired: () -> Void

    // MARK: - Form state
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var tosAccepted = false

    // MARK: - Loading / error state
    @State private var isCreateSubmitting = false
    @State private var isGoogleSubmitting = false
    @State private var isAppleSubmitting = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var isAlertPresented = false

    @State private var isLocalStorageAlertPresented = false

    // MARK: - Legal document sheet state
    @State private var legalDocument: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("AirWhisperLogoLightmode")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 278, height: 64)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Text("Create Account")
                    .font(.system(size: 30, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                AuthTextField(placeholder: "Full Name", text: $name, fontSize: 16)

                AuthTextField(
                    placeholder: "Email",
                    text: $email,
                    keyboardType: .emailAddress,
                    fontSize: 16
                )

                AuthTextField(placeholder: "Password", text: $password, isSecure: true, fontSize: 16)

                // MARK: Terms of Service row (checkbox + tappable legal links)
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        tosAccepted.toggle()
                    } label: {
                        Image(systemName: tosAccepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundStyle(tosAccepted ? Design.brandBlue : Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Terms of Service")
                    .accessibilityHint("Toggles acceptance of the Terms of Service.")
                    .accessibilityValue(tosAccepted ? "Checked" : "Unchecked")

                    tosAgreementLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)

                submitButton

                // MARK: Switch to Sign In
                TextLinkButton(
                    title: "Already have an account? Sign In",
                    accentRange: "Sign In",
                    fontSize: 15,
                    action: switchToSignIn
                )
                .frame(height: 44)

                // MARK: Divider
                orDivider

                // MARK: Social sign-in
                googleButton
                appleButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Design.background.ignoresSafeArea())
        .alert(isPresented: $isAlertPresented) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Data Stored Locally", isPresented: $isLocalStorageAlertPresented) {
            Button("Got it") {
                onWatchOnboardingRequired()
            }
        } message: {
            Text("Your AirWhisper data — phrases, contacts, settings, and history — will be saved on this device only. It will not be synced or backed up across other devices. To enable cross-device sync, sign in with Apple ID.")
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document) {
                legalDocument = nil
            }
        }
    }

    // MARK: - ToS agreement label (ported from LegalAgreementLabelController)

    private var tosAgreementLabel: some View {
        HStack(spacing: 0) {
            Text("I agree to the ")
            Button {
                legalDocument = LegalDocument.load(.termsOfService)
            } label: {
                Text("Terms of Service")
                    .underline()
                    .foregroundStyle(Design.link)
            }
            Text(" and ")
            Button {
                legalDocument = LegalDocument.load(.privacyPolicy)
            } label: {
                Text("Privacy Policy")
                    .underline()
                    .foregroundStyle(Design.link)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .tint(Design.link)
        .buttonStyle(.plain)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel("I agree to the Terms of Service and Privacy Policy")
        .accessibilityHint("Activates the Terms of Service or Privacy Policy.")
        .accessibilityAction(named: Text("View Terms of Service")) {
            legalDocument = LegalDocument.load(.termsOfService)
        }
        .accessibilityAction(named: Text("View Privacy Policy")) {
            legalDocument = LegalDocument.load(.privacyPolicy)
        }
    }

    // MARK: - Divider (storyboard: "OR" divider container)

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
            Text("OR")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
        }
        .frame(height: 20)
    }

    // MARK: - Submit button loading state

    private var submitButton: some View {
        Button {
            createAccountTapped()
        } label: {
            ZStack {
                if isCreateSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Create Account")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Design.brandBlue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!tosAccepted || isCreateSubmitting)
        .opacity(tosAccepted ? 1 : 0.45)
        .accessibilityLabel("Create Account")
    }

    // MARK: - Social buttons (same visual language as SignInView)

    private var googleButton: some View {
        Button {
            handleGoogleSignInTapped()
        } label: {
            HStack(spacing: 8) {
                if let logo = Self.googleLogoImage {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Design.neutralButton)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isGoogleSubmitting)
        .accessibilityLabel("Continue with Google")
        .accessibilityHint("Signs in using your Google account.")
    }

    private var appleButton: some View {
        Button {
            handleAppleIDSignInTapped()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 16))
                if isAppleSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Continue with Apple")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isAppleSubmitting)
        .accessibilityLabel("Continue with Apple")
        .accessibilityHint("Signs in using your Apple ID.")
    }

    private static var googleLogoImage: UIImage? {
        if let image = UIImage(named: "google_logo") { return image }
        // GoogleSignIn framework bundle fallback
        if let bundleURL = Bundle(for: GIDSignIn.self).url(forResource: "google_logo", withExtension: "png") {
            return UIImage(contentsOfFile: bundleURL.path)
        }
        return nil
    }

    // MARK: - Alerts (ported showAlert)

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        isAlertPresented = true
    }

    // MARK: - Actions (ported 1:1)

    private func createAccountTapped() {
        // 1. Name must not be empty
        guard !name.isEmpty else {
            showAlert(title: "Missing Name", message: "Please enter your full name.")
            return
        }
        // 2. Name must not contain digits
        guard name.rangeOfCharacter(from: .decimalDigits) == nil else {
            showAlert(title: "Invalid Name", message: "Name cannot contain numbers.")
            return
        }
        // 3. Email must be non-empty and contain "@"
        guard !email.isEmpty, email.contains("@") else {
            showAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }
        // 4. Password complexity
        guard password.count >= 8,
              password.rangeOfCharacter(from: .letters) != nil,
              password.rangeOfCharacter(from: .decimalDigits) != nil,
              password.rangeOfCharacter(from: .alphanumerics.inverted) != nil else {
            showAlert(
                title: "Weak Password",
                message: "Password must be at least 8 characters and include a letter, a number, and a special character."
            )
            return
        }
        // 5. Terms of Service must be accepted
        guard tosAccepted else {
            showAlert(title: "Terms of Service", message: "Please accept the Terms of Service to continue.")
            return
        }

        isCreateSubmitting = true
        Task { [self] in
            defer { Task { @MainActor in self.isCreateSubmitting = false } }
            do {
                try await AuthService.register(name: name, email: email, password: password)
                await MainActor.run { self.onRequestOTP(.emailVerification(email: email)) }
            } catch AuthError.unverified(_) {
                await MainActor.run { self.onRequestOTP(.emailVerification(email: email)) }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Registration Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func handleGoogleSignInTapped() {
        guard let presenting = topMostViewController() else {
            showAlert(title: "Sign In Failed", message: "Unable to present Google sign-in.")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { [self] result, error in
            Task { @MainActor [self] in
                if let error {
                    self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                    return
                }

                guard let user = result?.user,
                      let idToken = user.idToken?.tokenString else {
                    self.showAlert(title: "Sign In Failed", message: "Unable to retrieve Google credentials.")
                    return
                }
                let googleEmail = user.profile?.email
                let givenName = user.profile?.givenName ?? ""
                let familyName = user.profile?.familyName ?? ""
                var derivedName = "\(givenName) \(familyName)".trimmingCharacters(in: .whitespacesAndNewlines)
                if derivedName.isEmpty {
                    derivedName = googleEmail?.components(separatedBy: "@").first?.capitalized ?? "Google User"
                }

                self.isGoogleSubmitting = true
                Task { @MainActor [self] in
                    defer { self.isGoogleSubmitting = false }
                    do {
                        let response = try await AuthService.googleSignIn(idToken: idToken)
                        StorageManager.shared.saveSession(
                            accessToken: response.accessToken,
                            refreshToken: response.refreshToken
                        )
                        StorageManager.shared.setAppleIDSession(false)
                        DataManager.shared.setupNewUser(
                            name: response.user.name,
                            email: response.user.email
                        )
                        self.isLocalStorageAlertPresented = true
                    } catch {
                        self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func handleAppleIDSignInTapped() {
        isAppleSubmitting = true

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        let handler = CreateAccountAppleSignInHandler()
        controller.delegate = handler
        controller.presentationContextProvider = handler
        self.appleSignInHandler = handler // retain for the duration of the flow
        currentController = controller

        handler.onSuccess = { [self] identityToken, authorizationCode, fullName, appleUserIdentifier in
            Task { [self] in
                defer { Task { @MainActor in self.isAppleSubmitting = false } }
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
                        self.onWatchOnboardingRequired()
                    }
                } catch {
                    await MainActor.run {
                        self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                    }
                }
            }
        }
        handler.onFailure = { [self] message in
            Task { @MainActor in
                self.isAppleSubmitting = false
                if let message {
                    self.showAlert(title: "Sign In Failed", message: message)
                }
            }
        }

        controller.performRequests()
    }

    // MARK: - Presentation helper (topmost view controller for GIDSignIn)

    private func topMostViewController(
        from base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    ) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topMostViewController(from: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topMostViewController(from: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController, presented is UIAlertController == false {
            return topMostViewController(from: presented)
        }
        return base
    }

    // Retain the Apple sign-in flow objects for its lifetime.
    @State private var appleSignInHandler: CreateAccountAppleSignInHandler?
    @State private var currentController: ASAuthorizationController?
}

// MARK: - Apple sign-in coordinator (distinct name: no collision with the old UIKit file)

private final class CreateAccountAppleSignInHandler: NSObject {
    var onSuccess: ((String, String, String?, String) -> Void)?
    var onFailure: ((String?) -> Void)?

    private func formattedFullName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

extension CreateAccountAppleSignInHandler: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            finishWithFailure("Unable to retrieve Apple credentials.")
            return
        }
        let callback = onSuccess
        onSuccess = nil
        onFailure = nil
        callback?(identityToken, authorizationCode, formattedFullName(from: credential.fullName), credential.user)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let callback = onFailure
        onSuccess = nil
        onFailure = nil
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            callback?(nil)
            return
        }
        callback?(error.localizedDescription)
    }

    private func finishWithFailure(_ message: String?) {
        let callback = onFailure
        onSuccess = nil
        onFailure = nil
        callback?(message)
    }
}

extension CreateAccountAppleSignInHandler: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
