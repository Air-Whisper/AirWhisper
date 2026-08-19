//  UserProfileViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 3  - Full logout: invalidates JWT, clears Google/Apple sessions,
//  wipes local data, and returns to the onboarding / Login screen.

import UIKit
import AuthenticationServices
import GoogleSignIn
import os

private let userProfileLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AirWhisper",
    category: "UserProfile"
)

class UserProfileViewController: UIViewController {

    @IBOutlet weak var emailContainerView: UIView!
    @IBOutlet weak var emailTitleLabel:    UILabel!
    @IBOutlet weak var emailValueLabel:    UILabel!
    @IBOutlet weak var nameContainerView:  UIView!
    @IBOutlet weak var nameTitleLabel:     UILabel!
    @IBOutlet weak var nameValueLabel:     UILabel!
    @IBOutlet weak var signOutButton:      UIButton!
    @IBOutlet weak var deleteAccountButton: UIButton!
    @IBOutlet weak var resetToDefaultButton: UIButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        configureDeleteAccountButton()
        loadUserData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadUserData()
    }


    private func loadUserData() {
        guard let user = DataManager.shared.currentUser else {
            emailTitleLabel.text = "Email"
            emailValueLabel.text = "Not logged in"
            nameValueLabel.text  = "-"
            return
        }
        nameValueLabel.text = user.name
        if let email = user.email, !email.isEmpty {
            emailTitleLabel.text = "Email"
            emailValueLabel.text = email
        } else {
            emailTitleLabel.text = "Contact"
            emailValueLabel.text = "Not provided"
        }
    }


    @IBAction func signOutButtonTapped(_ sender: UIButton) {
        let alert = UIAlertController(title: "Sign Out",
                                      message: "Are you sure you want to sign out?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { [weak self] _ in
            self?.performSignOut()
        })
        present(alert, animated: true)
    }

    private func performSignOut() {
        // 1. Sign out Google if present
        GIDSignIn.sharedInstance.signOut()

        // 2. Revoke Apple session if present (best-effort; always continues)
        if let appleId = DataManager.shared.currentUser?.appleUserIdentifier {
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleId) { _, _ in }
        }

        // 3. Invalidate JWT on server (fire-and-forget) + clear local session
        Task {
            await AuthService.logout()

            await MainActor.run {
                // 4. Wipe all user data (includes StorageManager.clearSession() via clearUser())
                DataManager.shared.clearUser()
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")

                // 5. Return to onboarding
                guard let sceneDelegate = self.view.window?.windowScene?.delegate as? SceneDelegate else { return }
                let storyboard = UIStoryboard(name: "Main", bundle: nil)
                if let onboardingVC = storyboard.instantiateInitialViewController() {
                    sceneDelegate.window?.rootViewController = onboardingVC
                    sceneDelegate.window?.makeKeyAndVisible()
                }
            }
        }
    }


    private func configureDeleteAccountButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Delete Account"
        configuration.baseForegroundColor = .systemRed
        configuration.baseBackgroundColor = .systemRed
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        deleteAccountButton.configuration = configuration
        deleteAccountButton.accessibilityLabel = "Delete Account"
        deleteAccountButton.accessibilityHint = "Permanently deletes your AirWhisper account and clears app data."
        deleteAccountButton.addTarget(self, action: #selector(deleteAccountButtonTapped(_:)), for: .touchUpInside)
        // Layout is defined in the storyboard - no programmatic constraints needed.
    }

    @objc private func deleteAccountButtonTapped(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Delete Account?",
            message: "This permanently erases your account, contacts, phrases, settings, and history. This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue", style: .destructive) { [weak self] _ in
            self?.requestDeletionOTP()
        })
        present(alert, animated: true)
    }

    private func requestDeletionOTP() {
        setAccountDeletionLoading(true)
        Task {
            do {
                try await AuthService.requestDeleteOTP()
                await MainActor.run {
                    setAccountDeletionLoading(false)
                    presentDeleteOTPScreen()
                }
            } catch {
                await MainActor.run {
                    setAccountDeletionLoading(false)
                    showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func presentDeleteOTPScreen() {
        let email = DataManager.shared.currentUser?.email ?? ""
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let vc = storyboard.instantiateViewController(
            withIdentifier: "DeleteAccountOTPViewController"
        ) as? DeleteAccountOTPViewController else { return }
        vc.email = email
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func setAccountDeletionLoading(_ loading: Bool) {
        var configuration = deleteAccountButton.configuration
        configuration?.title = loading ? "Deleting..." : "Delete Account"
        configuration?.showsActivityIndicator = loading
        deleteAccountButton.configuration = configuration
        deleteAccountButton.isEnabled = !loading
        signOutButton.isEnabled = !loading
    }

    private func routeToOnboarding() {
        guard let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate else { return }
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let onboardingVC = storyboard.instantiateInitialViewController() {
            sceneDelegate.window?.rootViewController = onboardingVC
            sceneDelegate.window?.makeKeyAndVisible()
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }


    @IBAction func resetToDefaultButtonTapped(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Reset to Default?",
            message: "Your watch sensitivity, voice guidance, tap detector settings, and quick phrases will return to defaults. Tap calibration will be cleared and you will need to redo it.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            self?.performResetToDefaults()
        })
        present(alert, animated: true)
    }

    private func performResetToDefaults() {
        DataManager.shared.resetSettingsToDefaults()
        showAlert(
            title: "Settings Reset",
            message: "Your watch settings and quick phrases are back to defaults. Tap calibration has been cleared — you will need to redo it the next time you enable tap detector."
        )
    }


    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTourIfNeeded()
    }

    private func showTourIfNeeded() {
        let steps: [CoachStep] = [
            CoachStep(targetView: nameContainerView,  message: "Your registered name is shown here.",           position: .below),
            CoachStep(targetView: emailContainerView, message: "Your email address.",                           position: .below),
            CoachStep(targetView: signOutButton,      message: "Tap to sign out and restart the onboarding flow.", position: .above),
            CoachStep(targetView: deleteAccountButton, message: "Permanently delete your account and app data here.", position: .above),
            CoachStep(targetView: resetToDefaultButton, message: "Reset watch settings to factory defaults and clear tap calibration.", position: .above),
        ]
        CoachMarkManager.shared.showTourIfNeeded(on: self, steps: steps, screenKey: "profile")
    }
}
