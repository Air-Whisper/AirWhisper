//  SetNewPasswordViewController.swift
//  AirWhisperCompanionApp

import UIKit

class SetNewPasswordViewController: UIViewController {

    @IBOutlet weak var newPasswordField: UITextField!
    @IBOutlet weak var setPasswordButton: UIButton!

    var resetToken: String = ""


    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        newPasswordField.applyStandardAuthStyle()
        newPasswordField.enablePasswordToggle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Show navigation bar so they can go back if they want (though they shouldn't need to)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }


    @IBAction func setPasswordTapped(_ sender: UIButton) {
        guard let pwd = newPasswordField.text,
              pwd.count >= 8,
              pwd.rangeOfCharacter(from: .letters) != nil,
              pwd.rangeOfCharacter(from: .decimalDigits) != nil,
              pwd.rangeOfCharacter(from: .alphanumerics.inverted) != nil else {
            showAlert(
                title: "Weak Password",
                message: "Password must be at least 8 characters and include a letter, a number, and a special character."
            )
            return
        }

        setPasswordButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.setPasswordButton.hideLoading()
                }
            }
            do {
                try await AuthService.resetPassword(resetToken: resetToken, newPassword: pwd)
                await MainActor.run {
                    let mainAuthVC = self.navigationController?.presentingViewController as? MainAuthViewController
                    self.dismiss(animated: true) {
                        mainAuthVC?.showToast(message: "Password has been changed successfully")
                    }
                }
            } catch {
                await MainActor.run { self.showAlert(title: "Reset Failed", message: error.localizedDescription) }
            }
        }
    }


    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
