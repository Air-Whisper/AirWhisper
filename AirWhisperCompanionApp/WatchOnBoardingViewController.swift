//
//  WatchOnBoardingViewController.swift
//  AirWhisperCompanionApp
//
//  Created by GEU on 23/03/26.
import UIKit
import WatchConnectivity

class WatchOnBoardingViewController: UIViewController {

    @IBOutlet weak var PairWatchButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        updateButtonState()
        configureAccessibility()
        
        // Listen for watch connectivity changes from WatchConnectivityManager
        NotificationCenter.default.addObserver(self, selector: #selector(watchConnectionChanged), name: Notification.Name("WatchConnectionStatusChanged"), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let sheet = sheetPresentationController {
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = false
    }
}
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateButtonState()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func watchConnectionChanged() {
        DispatchQueue.main.async {
            self.updateButtonState()
        }
    }
    
   
    func updateButtonState() {
        guard WCSession.isSupported() else {
            PairWatchButton.setTitle("Continue", for: .normal)
            PairWatchButton.accessibilityLabel = "Continue to app"
            PairWatchButton.accessibilityValue = "Watch connectivity unavailable"
            PairWatchButton.accessibilityHint = "Continues without Apple Watch pairing."
            return
        }
        let session = WCSession.default
        if session.isPaired {
            PairWatchButton.setTitle("Next", for: .normal)
            PairWatchButton.accessibilityLabel = "Next"
            PairWatchButton.accessibilityValue = "Apple Watch paired"
            PairWatchButton.accessibilityHint = "Continues to the AirWhisper app."
        } else {
            PairWatchButton.setTitle("Pair My Watch", for: .normal)
            PairWatchButton.accessibilityLabel = "Pair My Watch"
            PairWatchButton.accessibilityValue = "Apple Watch not paired"
            PairWatchButton.accessibilityHint = "Opens options to pair a watch or continue without one."
        }
    }

    private func configureAccessibility() {
        PairWatchButton.accessibilityTraits = [.button]
    }
    
    
    @IBAction func PairWatchButtonTapped(_ sender: UIButton) {
        guard WCSession.isSupported() else {
            UserDefaults.standard.set(true, forKey: "skipWatchPairing")
            routeToMainApp()
            return
        }
        let session = WCSession.default
        
        if session.isPaired && session.isWatchAppInstalled {
            // Watch paired + app installed → Go to home
            UserDefaults.standard.set(false, forKey: "skipWatchPairing")
            routeToMainApp()
        }
        else if session.isPaired && !session.isWatchAppInstalled {
            // Watch paired + app NOT installed → Show option to continue or open watch settings
            let alert = UIAlertController(
                title: "Watch App Not Installed",
                message: "Please install the AirWhisper app on your Apple Watch. You can also continue and install it later.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Install Later", style: .default) { [weak self] _ in
                UserDefaults.standard.set(true, forKey: "skipWatchPairing")
                self?.routeToMainApp()
            })
            alert.addAction(UIAlertAction(title: "Open Watch Settings", style: .default) { [weak self] _ in
                self?.openWatchApp()
            })
            present(alert, animated: true)
        }
        else {
            // Watch not paired → Show option to continue or pair watch
            let alert = UIAlertController(
                title: "Apple Watch Not Found",
                message: "AirWhisper works best with an Apple Watch. You can still manage contacts, phrases, and history without one.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Continue anyway", style: .default) { [weak self] _ in
                UserDefaults.standard.set(true, forKey: "skipWatchPairing")
                self?.routeToMainApp()
            })
            alert.addAction(UIAlertAction(title: "Pair Watch", style: .default) { [weak self] _ in
                self?.openWatchApp()
            })
            present(alert, animated: true)
        }
    }
    
    func openWatchApp() {
        if let url = URL(string: "itms-watchs://") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { [weak self] didOpen in
                    if !didOpen {
                        self?.showWatchSettingsUnavailableAlert()
                    }
                }
            } else {
                showWatchSettingsUnavailableAlert()
            }
        }
    }

    private func showWatchSettingsUnavailableAlert() {
        let alert = UIAlertController(
            title: "Watch Settings Unavailable",
            message: "Unable to open Apple Watch pairing settings. You can still proceed to use the companion app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Continue to App", style: .default) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "skipWatchPairing")
            self?.routeToMainApp()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    private func handleWatchPairingState() {
        let isPaired = WCSession.isSupported() && WCSession.default.isPaired
        if isPaired {
            routeToMainApp()
        } else {
            showWatchUnpairedAlert()
        }
    }

    private func showWatchUnpairedAlert() {
        let alert = UIAlertController(
            title: "Apple Watch Not Found",
            message: "AirWhisper works best with an Apple Watch. You can still manage contacts, phrases, and history without one.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            UserDefaults.standard.set(true, forKey: "skipWatchPairing")
            self?.routeToMainApp()
        })
        present(alert, animated: true)
    }

    private func routeToMainApp() {
        guard DataManager.shared.currentUser != nil, StorageManager.shared.hasValidSession() else {
            StorageManager.shared.clearSession()
            UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            showAlert(
                title: "Sign In Required",
                message: "Please sign in again before entering AirWhisper."
            )
            return
        }

        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        NotificationCenter.default.post(name: Notification.Name("WatchConnectionStatusChanged"), object: nil)
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let tabBar = storyboard.instantiateViewController(withIdentifier: "TabBarController") as? UITabBarController else {
            // Storyboard ID missing - dismiss this sheet so the user is not stranded
            dismiss(animated: true)
            return
        }
        view.window?.rootViewController = tabBar
        view.window?.makeKeyAndVisible()
        WatchConnectivityManager.shared.sendStoredJWTTokenIfAvailable()
    }

    func goToNextScreen() {
        handleWatchPairingState()
    }
    
    func showAlert(message: String) {
        showAlert(title: "AirWhisper", message: message)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
