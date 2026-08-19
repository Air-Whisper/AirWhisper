import UIKit
import WatchConnectivity
import AuthenticationServices
import GoogleSignIn

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // UIResponder along with UIWindowSceneDelegate allows the scene to respond to events and manage the lifecycle of the scene, such as when it connects, becomes active, resigns active, enters foreground/background.

    var window: UIWindow? // stores the main window of the app which displays the content, can be empty too making it optional. But without it, nothing will appear on screen.
    var blockerWindow: UIWindow? // overlay window for watch disconnections

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
    // initializing any UIscene when it connects to the app, with options to handle any specific connection scenarios (like opening from a URL, or any other place).

    {
        guard let windowScene = (scene as? UIWindowScene) else { return } // converting the generic UIScene to a UIWindowScene becaise only UIWindowScene can display UI windows, and if it fails to convert, we return early to avoid any issues.

        window = UIWindow(windowScene: windowScene) // creates a new window attached to the windowscene.

        let storyboard = UIStoryboard(name: "Main", bundle: nil) // loading the storyboard file.

        DataManager.shared.startCloudSync()
        // begin listening for iCloud changes from other devices immediately at launch.

        let didLoadLocal = DataManager.shared.loadSavedData()
        let didRestoreCloud = !didLoadLocal && DataManager.shared.restoreFromCloudIfNeeded()
        // try local data first; if missing, check iCloud for a profile from another device (same Apple ID).

        let hasUserProfile = didLoadLocal || didRestoreCloud || DataManager.shared.currentUser != nil
        let hasValidSession = StorageManager.shared.hasValidSession()

        if hasUserProfile && hasValidSession {
            if didRestoreCloud {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                // mark onboarding as seen since the user already set up on another device.
            }
            let tabBarController = storyboard.instantiateViewController(withIdentifier: "TabBarController")
            window?.rootViewController = tabBarController
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            WatchConnectivityManager.shared.sendStoredJWTTokenIfAvailable()
        } else {
            // A saved profile without a valid token must not enter the authenticated app.
            StorageManager.shared.clearSession()
            UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            if let mainVC = storyboard.instantiateInitialViewController() {
                window?.rootViewController = mainVC
            }
        }
        // if there is no saved user profile locally or in iCloud, show onboarding. If a cloud profile was restored, skip straight to the main app.

        window?.makeKeyAndVisible() // displays the window and makes it enabled to recieve user interactions.

        // Setup the Watch Disconnect Overlay
        blockerWindow = UIWindow(windowScene: windowScene)
        let watchVC = storyboard.instantiateViewController(withIdentifier: "WatchOnBoardingViewController")
        blockerWindow?.rootViewController = watchVC
        blockerWindow?.windowLevel = .alert + 1
        blockerWindow?.isHidden = true // hidden initially

        NotificationCenter.default.addObserver(self, selector: #selector(handleWatchConnection), name: Notification.Name("WatchConnectionStatusChanged"), object: nil)

        // Initial manual trigger check
        handleWatchConnection()
    }

    @objc func handleWatchConnection() {
        DispatchQueue.main.async {
            let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
            guard hasSeenOnboarding else { return } // Don't interfere during onboarding!
            guard WCSession.isSupported() else {
                self.blockerWindow?.isHidden = true
                return
            }

            let session = WCSession.default
            if session.isPaired {
                UserDefaults.standard.set(false, forKey: "skipWatchPairing")
                self.blockerWindow?.isHidden = true
            } else {
                let skipWatchPairing = UserDefaults.standard.bool(forKey: "skipWatchPairing")
                if skipWatchPairing {
                    self.blockerWindow?.isHidden = true
                } else {
                    self.blockerWindow?.isHidden = false
                }
            }
        }
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
            self?.routeToMainApp()
        })
        window?.rootViewController?.present(alert, animated: true)
    }

    private func routeToMainApp() {
        guard DataManager.shared.currentUser != nil, StorageManager.shared.hasValidSession() else {
            StorageManager.shared.clearSession()
            UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            return
        }

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let tabBar = storyboard.instantiateViewController(withIdentifier: "TabBarController") as? UITabBarController else {
            // Storyboard ID missing - fall back to re-showing onboarding so the user isn't stranded
            if let fallback = storyboard.instantiateInitialViewController() {
                window?.rootViewController = fallback
                window?.makeKeyAndVisible()
            }
            return
        }
        window?.rootViewController = tabBar
        window?.makeKeyAndVisible()
        WatchConnectivityManager.shared.sendStoredJWTTokenIfAvailable()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        handleWatchConnection()
        checkAppleCredentialIfNeeded()
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
    }
    // lifecycle methods for the app.

    private func checkAppleCredentialIfNeeded() {
        // Only verify credentials if the user has completed onboarding and is in the main app
        guard UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        guard let appleUserId = DataManager.shared.currentUser?.appleUserIdentifier else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { state, _ in
            if state == .revoked {
                DispatchQueue.main.async {
                    DataManager.shared.clearCurrentUser()
                    StorageManager.shared.clearSession()
                    UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    let storyboard = UIStoryboard(name: "Main", bundle: nil)
                    if let onboardingVC = storyboard.instantiateInitialViewController() {
                        self.window?.rootViewController = onboardingVC
                        self.window?.makeKeyAndVisible()
                    }
                }
            }
        }
    }
}
