//  CreateAccountViewController.swift <!-- DEPRECATED -->
//  AirWhisperCompanionApp
//
//  Phase 3  - Wired to AuthService: registers the user, then pushes OTPVerificationViewController.
//  Google and Apple paths remain local (no OTP required for OAuth identities).

import UIKit
import AuthenticationServices
import GoogleSignIn

class CreateAccountViewController: UIViewController {


    @IBOutlet weak var nameField:     UITextField!
    @IBOutlet weak var emailField:    UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var tosCheckbox:   UIButton!
    @IBOutlet weak var createButton:  UIButton!


    private var tosAccepted: Bool = false {
        didSet { updateCreateButtonState() }
    }
    private weak var activeAppleSignInButton: UIButton?
    private var legalAgreementLabelController: LegalAgreementLabelController?


    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        syncCheckboxImage()
        updateCreateButtonState()
        configureAccessibility()
        configureLegalAgreementLabelIfPresent()
    }


    @IBAction func closeTapped(_ sender: UIButton) { dismiss(animated: true) }

    @IBAction func tosCheckboxTapped(_ sender: UIButton) {
        tosAccepted.toggle()
        syncCheckboxImage()
    }

    @IBAction func createAccountTapped(_ sender: UIButton) {
        guard let name = nameField.text, !name.isEmpty else {
            showAlert(title: "Missing Name", message: "Please enter your full name.")
            return
        }
        guard let email = emailField.text, !email.isEmpty else {
            showAlert(title: "Missing Email", message: "Please enter your email address.")
            return
        }
        guard let password = passwordField.text, password.count >= 6 else {
            showAlert(title: "Password Too Short", message: "Password must be at least 6 characters.")
            return
        }
        guard tosAccepted else {
            showAlert(title: "Terms of Service", message: "Please accept the Terms of Service to continue.")
            return
        }

        sender.isEnabled = false
        Task {
            defer { DispatchQueue.main.async { sender.isEnabled = true } }
            do {
                try await AuthService.register(name: name, email: email, password: password)
                await MainActor.run {
                    self.pushOTPScreen(email: email)
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Registration Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @IBAction func handleGoogleSignInTapped(_ sender: UIButton) {
        GIDSignIn.sharedInstance.signIn(withPresenting: self) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                self.showAlert(title: "Sign In Failed", message: "Unable to retrieve Google credentials.")
                return
            }
            let email     = user.profile?.email
            let givenName = user.profile?.givenName ?? ""
            let family    = user.profile?.familyName ?? ""
            var name      = "\(givenName) \(family)".trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = email?.components(separatedBy: "@").first?.capitalized ?? "Google User" }

            sender.isEnabled = false
            Task {
                defer { DispatchQueue.main.async { sender.isEnabled = true } }
                do {
                    let response = try await AuthService.googleSignIn(idToken: idToken)
                    await MainActor.run {
                        StorageManager.shared.saveSession(
                            accessToken:  response.accessToken,
                            refreshToken: response.refreshToken
                        )
                        DataManager.shared.setupNewUser(
                            name:  response.user.name,
                            email: response.user.email
                        )
                        self.navigateToWatchOnboarding()
                    }
                } catch {
                    await MainActor.run {
                        self.showAlert(title: "Sign In Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    @IBAction func handleAppleIDSignInTapped(_ sender: Any) {
        let button = sender as? UIButton
        activeAppleSignInButton = button
        button?.showLoading()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }


    private func pushOTPScreen(email: String) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let otpVC = storyboard.instantiateViewController(
            withIdentifier: "OTPVerificationViewController"
        ) as? OTPVerificationViewController else { return }
        otpVC.mode = .emailVerification(email: email)
        // Present over the current sheet
        otpVC.modalPresentationStyle = .pageSheet
        present(otpVC, animated: true)
    }

    private func navigateToWatchOnboarding() {
        dismiss(animated: true) {
            if let mainAuthVC = self.presentingViewController as? MainAuthViewController {
                mainAuthVC.performSegue(withIdentifier: "ShowWatchOnboarding", sender: mainAuthVC)
            }
        }
    }


    private func syncCheckboxImage() {
        let symbolName = tosAccepted ? "checkmark.square.fill" : "square"
        tosCheckbox.setImage(UIImage(systemName: symbolName), for: .normal)
        tosCheckbox.tintColor = tosAccepted
            ? UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)
            : .secondaryLabel
        updateCheckboxAccessibility()
    }

    private func updateCreateButtonState() {
        createButton.alpha = tosAccepted ? 1.0 : 0.45
        createButton.isUserInteractionEnabled = tosAccepted
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func configureAccessibility() {
        updateCheckboxAccessibility()
        configureSocialAuthButtonsAccessibility()
    }

    private func configureLegalAgreementLabelIfPresent() {
        guard let label = findLegalAgreementLabel(in: view) else { return }

        legalAgreementLabelController = LegalAgreementLabelController(label: label) { [weak self] document in
            self?.presentLegalDocument(document)
        }
    }

    private func findLegalAgreementLabel(in rootView: UIView) -> UILabel? {
        for subview in rootView.subviews {
            if let label = subview as? UILabel,
               label.text == "I agree to the Terms of Service and Privacy Policy" {
                return label
            }

            if let label = findLegalAgreementLabel(in: subview) {
                return label
            }
        }

        return nil
    }

    private func updateCheckboxAccessibility() {
        tosCheckbox.accessibilityLabel = "Terms of Service"
        tosCheckbox.accessibilityHint = "Toggles acceptance of the Terms of Service."
        tosCheckbox.accessibilityValue = tosAccepted ? "Checked" : "Unchecked"

        var traits: UIAccessibilityTraits = [.button]
        if tosAccepted {
            traits.insert(.selected)
        }
        tosCheckbox.accessibilityTraits = traits
    }

    private func configureSocialAuthButtonsAccessibility() {
        for button in buttons(in: view) {
            let actions = button.actions(forTarget: self, forControlEvent: .touchUpInside) ?? []
            if actions.contains("handleGoogleSignInTapped:") {
                button.accessibilityLabel = "Continue with Google"
                button.accessibilityHint = "Signs in using your Google account."
            } else if actions.contains("handleAppleIDSignInTapped:") {
                button.accessibilityLabel = "Continue with Apple"
                button.accessibilityValue = nil
                button.accessibilityHint = "Signs in using your Apple ID."
            }
        }
    }

    private func buttons(in rootView: UIView) -> [UIButton] {
        rootView.subviews.flatMap { subview -> [UIButton] in
            var result = buttons(in: subview)
            if let button = subview as? UIButton {
                result.append(button)
            }
            return result
        }
    }

    private func formattedFullName(from components: PersonNameComponents?) -> String? {
        guard let components = components else { return nil }
        let name = PersonNameComponentsFormatter()
            .string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    @MainActor
    private func finishAppleSignInLoading() {
        activeAppleSignInButton?.hideLoading()
        activeAppleSignInButton = nil
    }

    @MainActor
    private func failAppleSignIn(message: String) {
        finishAppleSignInLoading()
        showAlert(title: "Sign In Failed", message: message)
    }
}


extension CreateAccountViewController: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            failAppleSignIn(message: "Unable to retrieve Apple credentials.")
            return
        }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = credential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
            failAppleSignIn(message: "Unable to retrieve Apple credentials.")
            return
        }

        let fullName = formattedFullName(from: credential.fullName)
        let appleUserIdentifier = credential.user

        Task { [weak self] in
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
                    DataManager.shared.setupNewUser(
                        name: response.user.name,
                        email: response.user.email,
                        appleUserIdentifier: appleUserIdentifier
                    )
                    self?.finishAppleSignInLoading()
                    self?.navigateToWatchOnboarding()
                }
            } catch {
                await MainActor.run {
                    self?.failAppleSignIn(message: error.localizedDescription)
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.activeAppleSignInButton?.hideLoading()
            self?.activeAppleSignInButton = nil
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            self?.showAlert(title: "Sign In Failed", message: error.localizedDescription)
        }
    }
}

extension CreateAccountViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }
}
