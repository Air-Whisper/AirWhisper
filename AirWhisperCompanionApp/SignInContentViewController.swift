//  SignInContentViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 4  - Embedded child VC for the "Sign In" form.
//  Hosted inside MainAuthViewController's containerView.
//  All navigation is delegated back to parentAuthVC.

import UIKit
import AuthenticationServices
import GoogleSignIn

class SignInContentViewController: UIViewController {


    @IBOutlet weak var emailField:    UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var switchButton:  UIButton!


    /// Set by MainAuthViewController immediately after instantiation.
    weak var parentAuthVC: MainAuthViewController?
    private weak var activeAppleSignInButton: UIButton?


    override func viewDidLoad() {
        super.viewDidLoad()
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        emailField.applyStandardAuthStyle()
        passwordField.applyStandardAuthStyle()
        passwordField.enablePasswordToggle()
        configureSwitchButtonTitle()
        configureAccessibility()
    }


    @IBAction func signInTapped(_ sender: UIButton) {
        guard let email = emailField.text, !email.isEmpty else {
            showAlert(title: "Missing Email", message: "Please enter your email address.")
            return
        }
        guard let password = passwordField.text, !password.isEmpty else {
            showAlert(title: "Missing Password", message: "Please enter your password.")
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
                let response = try await AuthService.login(email: email, password: password)
                StorageManager.shared.saveSession(
                    accessToken:  response.accessToken,
                    refreshToken: response.refreshToken
                )
                StorageManager.shared.setAppleIDSession(false)
                DataManager.shared.setupNewUser(
                    name:  response.user.name,
                    email: response.user.email
                )
                await MainActor.run {
                    self.showLocalStorageAlert {
                        self.parentAuthVC?.navigateToWatchOnboarding()
                    }
                }
            } catch AuthError.unverified(_) {
                await MainActor.run {
                    showAlert(title: "Account Unverified", message: "Please verify your email and create an account.")
                }
            } catch {
                await MainActor.run { showAlert(title: "Sign In Failed", message: error.localizedDescription) }
            }
        }
    }


    @IBAction func forgotPasswordTapped(_ sender: UIButton) {
        parentAuthVC?.showForgotPassword()
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


    @IBAction func switchToCreateAccountTapped(_ sender: UIButton) {
        parentAuthVC?.showCreateAccountContent()
    }


    private func configureSwitchButtonTitle() {
        let title = "Don't have an account? Create Account"
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
            range: (title as NSString).range(of: "Create Account")
        )

        switchButton.setAttributedTitle(attributedTitle, for: .normal)
    }

    private func configureAccessibility() {
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


extension SignInContentViewController: ASAuthorizationControllerDelegate {
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

extension SignInContentViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // view.window can be nil during navigation transitions; fall back to a new window
        // rather than crashing with a force-unwrap failure.
        return self.view.window ?? UIWindow()
    }
}
