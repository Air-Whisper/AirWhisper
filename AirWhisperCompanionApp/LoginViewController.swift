//  LoginViewController.swift
//  AirWhisperCompanionApp
//
//  Phase 4  - MainAuthViewController: container that embeds either
//  CreateAccountContentViewController (default) or SignInContentViewController.
//  All sign-in / create-account logic lives in the child VCs; this class
//  owns only the container view, child-swap plumbing, and modal navigation.

import UIKit

class MainAuthViewController: UIViewController {


    @IBOutlet weak var containerView: UIView!


    private var activeChild: UIViewController?


    override func viewDidLoad() {
        super.viewDidLoad()
        showCreateAccountContent()
    }


    func showCreateAccountContent() {
        transition(to: makeCreateAccountVC())
    }

    func showSignInContent() {
        transition(to: makeSignInVC())
    }

    private func makeCreateAccountVC() -> CreateAccountContentViewController {
        let vc = UIStoryboard(name: "Main", bundle: nil)
            .instantiateViewController(withIdentifier: "CreateAccountContentViewController")
            as! CreateAccountContentViewController
        vc.parentAuthVC = self
        return vc
    }

    private func makeSignInVC() -> SignInContentViewController {
        let vc = UIStoryboard(name: "Main", bundle: nil)
            .instantiateViewController(withIdentifier: "SignInContentViewController")
            as! SignInContentViewController
        vc.parentAuthVC = self
        return vc
    }

    private func transition(to newChild: UIViewController) {
        // 1. Remove existing child if present
        if let old = activeChild {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }

        // 2. Embed the new child
        addChild(newChild)
        // NOTE: frame + autoresizingMask here are required for child VC embedding
        // and are not layout decisions  - the container view's own constraints
        // (set in the storyboard) drive all actual layout.
        newChild.view.frame = containerView.bounds
        newChild.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(newChild.view)
        newChild.didMove(toParent: self)

        activeChild = newChild
    }


    func navigateToWatchOnboarding() {
        performSegue(withIdentifier: "ShowWatchOnboarding", sender: self)
    }

    func showOTPVerification(mode: OTPMode) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let otpVC = storyboard.instantiateViewController(
            withIdentifier: "OTPVerificationViewController"
        ) as? OTPVerificationViewController else { return }
        otpVC.mode = mode
        otpVC.parentAuthVC = self
        otpVC.modalPresentationStyle = .pageSheet
        present(otpVC, animated: true)
    }

    func showForgotPassword() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let fpVC = storyboard.instantiateViewController(
            withIdentifier: "ForgotPasswordViewController"
        ) as? ForgotPasswordViewController else { return }
        
        let navController = UINavigationController(rootViewController: fpVC)
        navController.modalPresentationStyle = .pageSheet
        present(navController, animated: true)
    }


    /// Displays a transient overlay message at the bottom of the screen.
    func showToast(message: String, duration: TimeInterval = 3.0) {
        let toast = UILabel()
        toast.text = message
        toast.textAlignment = .center
        toast.font = UIFontMetrics.default.scaledFont(
            for: UIFont.systemFont(ofSize: 14, weight: .medium)
        )
        toast.adjustsFontForContentSizeCategory = true
        toast.textColor = .white
        toast.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85)
        toast.layer.cornerRadius = 12
        toast.clipsToBounds = true
        toast.numberOfLines = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.3, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.4, delay: duration, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
}
