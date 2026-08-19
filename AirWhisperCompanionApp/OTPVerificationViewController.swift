//  OTPVerificationViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 4  - Redesigned OTP entry screen with 6 individual digit fields.
//  Handles one mode only:
//    • .emailVerification  - verifies new-account OTP then navigates to Watch Onboarding.
//  The .passwordReset path has been moved to ForgotPasswordViewController.

import UIKit

enum OTPMode {
    case emailVerification(email: String)
}

class OTPVerificationViewController: UIViewController, UITextFieldDelegate {


    @IBOutlet weak var titleLabel:    UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var otpStackView:  UIStackView!
    @IBOutlet weak var verifyButton:  UIButton!
    @IBOutlet weak var resendButton:  UIButton!

    // 6 individual text fields
    @IBOutlet var otpFields: [UITextField]!

    weak var parentAuthVC: MainAuthViewController?

    var mode: OTPMode = .emailVerification(email: "")

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
        guard case .emailVerification(let email) = mode else { return }
        titleLabel.text    = "We just sent an email"
        subtitleLabel.text = "Enter the security code we sent to\n\(email)"
        configureResendButtonTitle()
        
        // Disable verify initially
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
            [.foregroundColor: UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)],
            range: (title as NSString).range(of: "Resend")
        )

        resendButton.setAttributedTitle(attributedTitle, for: .normal)
    }

    private func setupOTPFields() {
        // Sort by tag to ensure correct order
        otpFields.sort { $0.tag < $1.tag }
        
        for field in otpFields {
            field.delegate = self
            field.font = UIFontMetrics.default.scaledFont(
                for: UIFont.systemFont(ofSize: 22, weight: .medium)
            )
            field.adjustsFontForContentSizeCategory = true
            field.layer.borderColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1).cgColor
            
            field.addTarget(self, action: #selector(otpFieldDidBeginEditing(_:)), for: .editingDidBegin)
            field.addTarget(self, action: #selector(otpFieldDidEndEditing(_:)), for: .editingDidEnd)
            field.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        }
    }


    // MARK: - Text Field Handling

    @objc private func textFieldDidChange(_ textField: UITextField) {
        let text = textField.text ?? ""
        
        // Restrict to single char
        if text.count > 1 {
            textField.text = String(text.prefix(1))
        }
        
        checkVerifyButton()
        
        // Move forward if filled
        if text.count == 1 {
            if let index = otpFields.firstIndex(of: textField), index < otpFields.count - 1 {
                otpFields[index + 1].becomeFirstResponder()
            } else {
                textField.resignFirstResponder()
                // Auto verify when all fields filled
                verifyButtonTapped(verifyButton)
            }
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty && (textField.text?.isEmpty ?? true) {
            // Backspace on empty field → move back
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
        sender.layer.borderColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1).cgColor
        sender.layer.borderWidth = 2
    }
    
    @objc private func otpFieldDidEndEditing(_ sender: UITextField) {
        sender.layer.borderColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1).cgColor
        sender.layer.borderWidth = 1
    }


    // MARK: - Actions

    @IBAction func verifyButtonTapped(_ sender: UIButton) {
        let code = otpFields.compactMap { $0.text }.joined()
        guard code.count == 6 else { return }
        guard case .emailVerification(let email) = mode else { return }
        verifyEmailOTP(email: email, code: code)
    }

    @IBAction func resendTapped(_ sender: UIButton) {
        guard case .emailVerification(let email) = mode else { return }
        resendVerificationCode(email: email)
    }


    // MARK: - Network

    private func verifyEmailOTP(email: String, code: String) {
        verifyButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.verifyButton.hideLoading()
                }
            }
            do {
                let response = try await AuthService.verifyEmail(email: email, code: code)
                // Persist tokens + user profile
                StorageManager.shared.saveSession(
                    accessToken:  response.accessToken,
                    refreshToken: response.refreshToken
                )
                await MainActor.run {
                    StorageManager.shared.setAppleIDSession(false)
                    DataManager.shared.setupNewUser(
                        name:  response.user.name,
                        email: response.user.email
                    )
                    showLocalStorageAlert {
                        self.navigateToWatchOnboarding()
                    }
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Verification Failed", message: error.localizedDescription)
                    // Clear fields on failure
                    otpFields.forEach { $0.text = "" }
                    otpFields.first?.becomeFirstResponder()
                    checkVerifyButton()
                }
            }
        }
    }

    private func resendVerificationCode(email: String) {
        resendButton.isEnabled = false
        Task {
            do {
                try await AuthService.resendVerification(email: email)
                await MainActor.run {
                    showAlert(title: "Code Resent", message: "A new code has been sent to \(email).")
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


    // MARK: - Resend Timer

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
            [.foregroundColor: UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)],
            range: (title as NSString).range(of: "Resend")
        )

        resendButton.setAttributedTitle(attributedTitle, for: .normal)
        resendButton.titleLabel?.textAlignment = .center
        resendButton.titleLabel?.numberOfLines = 0
    }


    // MARK: - Navigation

    private func navigateToWatchOnboarding() {
        let authVC = self.parentAuthVC
        dismiss(animated: true) {
            authVC?.navigateToWatchOnboarding()
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


    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    deinit {
        resendTimer?.invalidate()
    }
}
