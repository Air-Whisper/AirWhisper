//  DeleteAccountOTPViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 5  - Red-themed OTP confirmation for account deletion.
//  Presented after the user confirms they want to delete their account
//  and the backend sends a deletion OTP to their email.

import UIKit
import GoogleSignIn
import os

private let deleteOTPLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AirWhisper",
    category: "DeleteAccountOTP"
)

class DeleteAccountOTPViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var titleLabel:    UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var otpStackView:  UIStackView!
    @IBOutlet weak var verifyButton:  UIButton!
    @IBOutlet weak var resendButton:  UIButton!

    @IBOutlet var otpFields: [UITextField]!

    var email: String = ""

    private var resendTimer: Timer?
    private var resendCountdown: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        setupOTPFields()

        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func configureUI() {
        titleLabel.text = "Confirm account deletion"
        let displayEmail = email.isEmpty ? "your registered address" : email
        subtitleLabel.text = "Enter the 6-digit code sent to\n\(displayEmail)"
        configureResendButtonTitle()

        verifyButton.isEnabled = false
        verifyButton.alpha = 0.5
    }

    private func configureResendButtonTitle() {
        let title = "Didn't receive code? Resend"
        let font = UIFont.preferredFont(forTextStyle: .callout)
        resendButton.titleLabel?.adjustsFontForContentSizeCategory = true
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: font
            ]
        )
        attributedTitle.addAttributes(
            [.foregroundColor: UIColor.systemRed],
            range: (title as NSString).range(of: "Resend")
        )
        resendButton.setAttributedTitle(attributedTitle, for: .normal)
    }

    private func setupOTPFields() {
        otpFields.sort { $0.tag < $1.tag }

        for field in otpFields {
            field.delegate = self
            field.font = UIFontMetrics.default.scaledFont(
                for: UIFont.systemFont(ofSize: 22, weight: .medium)
            )
            field.adjustsFontForContentSizeCategory = true
            field.layer.borderColor = UIColor.systemRed.cgColor

            field.addTarget(self, action: #selector(otpFieldDidBeginEditing(_:)), for: .editingDidBegin)
            field.addTarget(self, action: #selector(otpFieldDidEndEditing(_:)), for: .editingDidEnd)
            field.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        }
    }

    @objc private func textFieldDidChange(_ textField: UITextField) {
        let text = textField.text ?? ""
        if text.count > 1 {
            textField.text = String(text.prefix(1))
        }
        checkVerifyButton()
        if text.count == 1 {
            if let index = otpFields.firstIndex(of: textField), index < otpFields.count - 1 {
                otpFields[index + 1].becomeFirstResponder()
            } else {
                textField.resignFirstResponder()
                verifyButtonTapped(verifyButton)
            }
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty && (textField.text?.isEmpty ?? true) {
            if let index = otpFields.firstIndex(of: textField), index > 0 {
                otpFields[index - 1].becomeFirstResponder()
                otpFields[index - 1].text = ""
                checkVerifyButton()
            }
            return false
        }
        return true
    }

    private func checkVerifyButton() {
        let code = otpFields.compactMap { $0.text }.joined()
        let isValid = code.count == 6
        verifyButton.isEnabled = isValid
        verifyButton.alpha = isValid ? 1.0 : 0.5
    }

    @objc private func otpFieldDidBeginEditing(_ sender: UITextField) {
        sender.layer.borderColor = UIColor.systemRed.cgColor
        sender.layer.borderWidth = 2
    }

    @objc private func otpFieldDidEndEditing(_ sender: UITextField) {
        sender.layer.borderColor = UIColor.systemRed.cgColor
        sender.layer.borderWidth = 1
    }

    @IBAction func verifyButtonTapped(_ sender: UIButton) {
        let code = otpFields.compactMap { $0.text }.joined()
        guard code.count == 6 else { return }
        confirmDeletion(code: code)
    }

    @IBAction func resendTapped(_ sender: UIButton) {
        resendDeletionOTP()
    }

    private func confirmDeletion(code: String) {
        verifyButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.verifyButton.hideLoading()
                }
            }
            do {
                try await AuthService.deleteAccount(code: code)
                await disconnectGoogleSessionIfNeeded()
                await MainActor.run {
                    DataManager.shared.clearUser(deleteCloudData: true, watchSignal: .accountDeleted)
                    UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    routeToOnboarding()
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Deletion Failed", message: error.localizedDescription)
                    otpFields.forEach { $0.text = "" }
                    otpFields.first?.becomeFirstResponder()
                    checkVerifyButton()
                }
            }
        }
    }

    private func resendDeletionOTP() {
        resendButton.isEnabled = false
        Task {
            do {
                try await AuthService.requestDeleteOTP()
                await MainActor.run {
                    showAlert(title: "Code Resent", message: "A new code has been sent to your registered email.")
                    startResendTimer()
                }
            } catch {
                await MainActor.run {
                    resendButton.isEnabled = true
                    showAlert(title: "Resend Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func startResendTimer() {
        resendCountdown = 60
        updateResendTimerTitle()
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.resendCountdown -= 1
            if self.resendCountdown <= 0 {
                timer.invalidate()
                self.resendTimer = nil
                self.resendButton.isEnabled = true
                self.configureResendButtonTitle()
            } else {
                self.updateResendTimerTitle()
            }
        }
    }

    private func updateResendTimerTitle() {
        let minutes = resendCountdown / 60
        let seconds = resendCountdown % 60
        let timeStr = String(format: "%02d : %02d", minutes, seconds)
        let title = "Didn't receive code?\nResend - \(timeStr)"
        let font = UIFont.preferredFont(forTextStyle: .callout)
        let attributedTitle = NSMutableAttributedString(
            string: title,
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: font
            ]
        )
        attributedTitle.addAttributes(
            [.foregroundColor: UIColor.systemRed],
            range: (title as NSString).range(of: "Resend")
        )
        resendButton.setAttributedTitle(attributedTitle, for: .normal)
        resendButton.titleLabel?.textAlignment = .center
        resendButton.titleLabel?.numberOfLines = 0
    }

    @MainActor
    private func disconnectGoogleSessionIfNeeded() async {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.disconnect { error in
                if let error = error {
                    deleteOTPLogger.error("Google disconnect failed during account deletion: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
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

    deinit {
        resendTimer?.invalidate()
    }
}
