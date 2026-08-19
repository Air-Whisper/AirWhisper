//  ForgotPasswordOTPViewController.swift
//  AirWhisperCompanionApp

import UIKit

class ForgotPasswordOTPViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var otpStackView: UIStackView!
    @IBOutlet weak var verifyButton: UIButton!
    @IBOutlet weak var resendButton: UIButton!

    // 6 individual text fields
    @IBOutlet var otpFields: [UITextField]!

    var email: String = ""


    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        setupOTPFields()
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }


    private func configureUI() {
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
        // Sort by tag if available (or assume they are connected in order)
        otpFields.sort { $0.tag < $1.tag }
        
        for field in otpFields {
            field.delegate = self
            field.font = UIFontMetrics.default.scaledFont(
                for: UIFont.systemFont(ofSize: 22, weight: .medium)
            )
            field.adjustsFontForContentSizeCategory = true
            field.layer.borderColor = UIColor.lightGray.cgColor
            
            field.addTarget(self, action: #selector(otpFieldDidBeginEditing(_:)), for: .editingDidBegin)
            field.addTarget(self, action: #selector(otpFieldDidEndEditing(_:)), for: .editingDidEnd)
            // Allow detecting backspace when empty
            field.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        }
    }

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
                // Auto verify?
                verifyButtonTapped(verifyButton)
            }
        }
    }

    // Handle backspace when empty (requires a custom subclass usually, but we can do a simplified version using delegate)
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty && (textField.text?.isEmpty ?? true) {
            // It's a backspace on an empty field
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


    @IBAction func verifyButtonTapped(_ sender: UIButton) {
        let code = otpFields.compactMap { $0.text }.joined()
        guard code.count == 6 else { return }

        verifyButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.verifyButton.hideLoading()
                }
            }
            do {
                let token = try await AuthService.verifyReset(email: email, code: code)
                await MainActor.run {
                    self.pushToNewPassword(token: token)
                }
            } catch {
                await MainActor.run {
                    self.showAlert(title: "Invalid Code", message: error.localizedDescription)
                    // clear fields
                    self.otpFields.forEach { $0.text = "" }
                    self.otpFields.first?.becomeFirstResponder()
                    self.checkVerifyButton()
                }
            }
        }
    }

    @IBAction func resendButtonTapped(_ sender: UIButton) {
        resendButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.resendButton.hideLoading()
                }
            }
            do {
                try await AuthService.forgotPassword(email: email)
                await MainActor.run {
                    self.showAlert(title: "Code Resent", message: "A new code has been sent to \(email).")
                }
            } catch {
                await MainActor.run { self.showAlert(title: "Error", message: error.localizedDescription) }
            }
        }
    }

    @objc private func otpFieldDidBeginEditing(_ sender: UITextField) {
        sender.layer.borderColor = UIColor.systemBlue.cgColor
        sender.layer.borderWidth = 2
    }
    
    @objc private func otpFieldDidEndEditing(_ sender: UITextField) {
        sender.layer.borderColor = UIColor.lightGray.cgColor
        sender.layer.borderWidth = 1
    }


    private func pushToNewPassword(token: String) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let newPwdVC = storyboard.instantiateViewController(withIdentifier: "SetNewPasswordViewController") as? SetNewPasswordViewController else { return }
        newPwdVC.resetToken = token
        navigationController?.pushViewController(newPwdVC, animated: true)
    }


    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
