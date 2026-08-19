//  CreateAccountContentViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 4  - Embedded child VC for the "Create Account" form.
//  Hosted inside MainAuthViewController's containerView.
//  All navigation is delegated back to parentAuthVC.

import UIKit
import AuthenticationServices
import GoogleSignIn

class CreateAccountContentViewController: UIViewController {


    @IBOutlet weak var nameField:     UITextField!
    @IBOutlet weak var emailField:    UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var tosCheckbox:   UIButton!
    @IBOutlet weak var tosLabel:      UILabel!
    @IBOutlet weak var createButton:  UIButton!
    @IBOutlet weak var switchButton:  UIButton!


    private var tosAccepted: Bool = false {
        didSet { updateCreateButtonState() }
    }
    private weak var activeAppleSignInButton: UIButton?
    private var legalAgreementLabelController: LegalAgreementLabelController?

    /// Set by MainAuthViewController immediately after instantiation.
    weak var parentAuthVC: MainAuthViewController?


    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        syncCheckboxImage()
        updateCreateButtonState()
        
        nameField.applyStandardAuthStyle()
        emailField.applyStandardAuthStyle()
        passwordField.applyStandardAuthStyle()
        passwordField.enablePasswordToggle()
        configureLegalAgreementLabel()
        configureSwitchButtonTitle()
        configureAccessibility()
    }


    @IBAction func tosCheckboxTapped(_ sender: UIButton) {
        tosAccepted.toggle()
        syncCheckboxImage()
    }

    @IBAction func createAccountTapped(_ sender: UIButton) {
        // 1. Name must not be empty
        guard let name = nameField.text, !name.isEmpty else {
            showAlert(title: "Missing Name", message: "Please enter your full name.")
            return
        }
        // 2. Name must not contain digits
        guard name.rangeOfCharacter(from: .decimalDigits) == nil else {
            showAlert(title: "Invalid Name", message: "Name cannot contain numbers.")
            return
        }
        // 3. Email must be non-empty and contain "@"
        guard let email = emailField.text, !email.isEmpty, email.contains("@") else {
            showAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }
        // 4. Password must meet all complexity requirements
        guard let password = passwordField.text,
              password.count >= 8,
              password.rangeOfCharacter(from: CharacterSet.letters) != nil,
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

        sender.showLoading()
        Task {
            defer { 
                DispatchQueue.main.async { 
                    sender.hideLoading()
                } 
            }
            do {
                try await AuthService.register(name: name, email: email, password: password)
                await MainActor.run {
                    parentAuthVC?.showOTPVerification(mode: .emailVerification(email: email))
                }
            } catch AuthError.unverified(_) {
                await MainActor.run {
                    parentAuthVC?.showOTPVerification(mode: .emailVerification(email: email))
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Registration Failed", message: error.localizedDescription)
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

            sender.showLoading()
            Task {
                defer { 
                    DispatchQueue.main.async { 
                        sender.hideLoading()
                    } 
                }
                do {
                    let response = try await AuthService.googleSignIn(idToken: idToken)
                    await MainActor.run {
                        StorageManager.shared.saveSession(
                            accessToken:  response.accessToken,
                            refreshToken: response.refreshToken
                        )
                        StorageManager.shared.setAppleIDSession(false)
                        DataManager.shared.setupNewUser(
                            name:  response.user.name,
                            email: response.user.email
                        )
                        self.showLocalStorageAlert {
                            self.parentAuthVC?.navigateToWatchOnboarding()
                        }
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

    @IBAction func switchToSignInTapped(_ sender: UIButton) {
        parentAuthVC?.showSignInContent()
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

    private func configureSwitchButtonTitle() {
        let title = "Already have an account? Sign In"
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        switchButton.titleLabel?.adjustsFontForContentSizeCategory = true
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: font
            ]
        )

        attributedTitle.addAttributes(
            [.foregroundColor: UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)],
            range: (title as NSString).range(of: "Sign In")
        )

        switchButton.setAttributedTitle(attributedTitle, for: .normal)
    }

    private func configureLegalAgreementLabel() {
        legalAgreementLabelController = LegalAgreementLabelController(label: tosLabel) { [weak self] document in
            self?.presentLegalDocument(document)
        }
    }

    private func configureAccessibility() {
        updateCheckboxAccessibility()
        configureSocialAuthButtonsAccessibility()
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

    private func showLocalStorageAlert(then completion: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Data Stored Locally",
            message: "Your AirWhisper data — phrases, contacts, settings, and history — will be saved on this device only. It will not be synced or backed up across other devices. To enable cross-device sync, sign in with Apple ID.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Got it", style: .default) { _ in
            completion()
        })
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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


extension CreateAccountContentViewController: ASAuthorizationControllerDelegate {
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
                    StorageManager.shared.setAppleIDSession(true)
                    DataManager.shared.setupNewUser(
                        name: response.user.name,
                        email: response.user.email,
                        appleUserIdentifier: appleUserIdentifier
                    )
                    self?.finishAppleSignInLoading()
                    self?.parentAuthVC?.navigateToWatchOnboarding()
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

extension CreateAccountContentViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // view.window can be nil during navigation transitions; fall back to a new window
        // rather than crashing with a force-unwrap failure.
        return self.view.window ?? UIWindow()
    }
}
