//  ForgotPasswordViewController.swift
//  AirWhisperCompanionApp

import UIKit

class ForgotPasswordViewController: UIViewController {

    @IBOutlet weak var emailStackView:        UIStackView!
    @IBOutlet weak var emailField:            UITextField!
    @IBOutlet weak var sendOTPButton:         UIButton!


    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup Navigation Bar
        let backItem = UIBarButtonItem()
        backItem.title = ""
        navigationItem.backBarButtonItem = backItem
        if #available(iOS 14.0, *) {
            navigationItem.backButtonDisplayMode = .minimal
        }
        // navigationItem.title = "Reset Password" // Title is set in Storyboard label
        
        let tap = UITapGestureRecognizer(target: view, action: #selector(UIView.endEditing))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        emailField.applyStandardAuthStyle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }


    @IBAction func sendOTPTapped(_ sender: UIButton) {
        guard let email = emailField.text, email.contains("@") else {
            showAlert(title: "Invalid Email", message: "Please enter a valid email address.")
            return
        }
        
        sendOTPButton.showLoading()
        Task {
            defer {
                DispatchQueue.main.async {
                    self.sendOTPButton.hideLoading()
                }
            }
            do {
                try await AuthService.forgotPassword(email: email)
                await MainActor.run {
                    self.pushToOTPVerification(email: email)
                }
            } catch {
                await MainActor.run { self.showAlert(title: "Error", message: error.localizedDescription) }
            }
        }
    }


    private func pushToOTPVerification(email: String) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let otpVC = storyboard.instantiateViewController(withIdentifier: "ForgotPasswordOTPViewController") as? ForgotPasswordOTPViewController else {
            return
        }
        otpVC.email = email
        navigationController?.pushViewController(otpVC, animated: true)
    }


    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
