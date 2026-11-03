import Foundation
import UIKit
import WatchConnectivity
import AuthenticationServices
import GoogleSignIn

/// Root navigation destination for the whole app.
///
/// Ports the root view-controller swapping previously done in `SceneDelegate`
/// (launch routing, sign-out routing, revoked-Apple-credential routing) and in
/// `WatchOnBoardingViewController` (post-onboarding routing).
enum AppRoute: Equatable {
    case onboarding
    case auth
    case watchPairing
    case main
}

/// Identifiable wrapper so the root view can present the same
/// `UIAlertController`-style alerts the UIKit version showed.
struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// Global app state: root routing, global alerts, watch pairing blocker.
///
/// This is a faithful port of the lifecycle logic that lived in
/// `SceneDelegate` + the root-view-controller swaps in the old code.
final class AppState: NSObject, ObservableObject {

    static let watchConnectionStatusChangedNotification = Notification.Name("WatchConnectionStatusChanged")

    @Published var route: AppRoute = .onboarding
    @Published var alert: AppAlert?
    @Published private(set) var isWatchBlockerVisible: Bool = false

    override init() {
        super.init()
        // Re-evaluate the blocker whenever connectivity status changes,
        // mirroring SceneDelegate's "WatchConnectionStatusChanged" observer.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWatchConnectionNotification),
            name: AppState.watchConnectionStatusChangedNotification,
            object: nil
        )
    }

    // MARK: - Launch (ported from SceneDelegate.scene(_:willConnectTo:))

    func handleLaunch() {
        // Begin listening for iCloud changes from other devices at launch.
        DataManager.shared.startCloudSync()

        // Try local data first; if missing, check iCloud for a profile from
        // another device (same Apple ID).
        let didLoadLocal = DataManager.shared.loadSavedData()
        let didRestoreCloud = !didLoadLocal && DataManager.shared.restoreFromCloudIfNeeded()

        let hasUserProfile = didLoadLocal || didRestoreCloud || DataManager.shared.currentUser != nil
        let hasValidSession = StorageManager.shared.hasValidSession()

        if hasUserProfile && hasValidSession {
            if didRestoreCloud {
                // Mark onboarding as seen since the user already set up on another device.
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            }
            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
            route = .main
            WatchConnectivityManager.shared.sendStoredJWTTokenIfAvailable()
        } else {
            // A saved profile without a valid token must not enter the authenticated app.
            StorageManager.shared.clearSession()
            UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            route = .onboarding
        }

        updateWatchBlockerState()
    }

    // MARK: - Scene lifecycle (ported from SceneDelegate.sceneDidBecomeActive(_:))

    func handleSceneActive() {
        // From handleWatchConnection()
        updateWatchBlockerState()
        // From checkAppleCredentialIfNeeded()
        checkAppleCredentialIfNeeded()
    }

    @objc private func handleWatchConnectionNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWatchBlockerState()
        }
    }

    /// Ported from SceneDelegate.handleWatchConnection() — controls the
    /// full-screen watch-pairing blocker window.
    private func updateWatchBlockerState() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
        guard hasSeenOnboarding else {
            // Don't interfere during onboarding!
            isWatchBlockerVisible = false
            return
        }
        guard WCSession.isSupported() else {
            isWatchBlockerVisible = false
            return
        }

        let session = WCSession.default
        if session.isPaired {
            UserDefaults.standard.set(false, forKey: "skipWatchPairing")
            isWatchBlockerVisible = false
        } else {
            let skipWatchPairing = UserDefaults.standard.bool(forKey: "skipWatchPairing")
            isWatchBlockerVisible = !skipWatchPairing
        }
    }

    // MARK: - Apple credential state (ported from SceneDelegate.checkAppleCredentialIfNeeded)

    private func checkAppleCredentialIfNeeded() {
        // Only verify credentials if the user has completed onboarding and is in the main app.
        guard UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        guard let appleUserId = DataManager.shared.currentUser?.appleUserIdentifier else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserId) { state, _ in
            if state == .revoked {
                DispatchQueue.main.async { [weak self] in
                    DataManager.shared.clearCurrentUser()
                    StorageManager.shared.clearSession()
                    UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                    self?.route = .onboarding
                }
            }
        }
    }

    // MARK: - Transitions

    /// Ported from WatchOnBoardingViewController.routeToMainApp().
    func completeWatchOnboarding() {
        guard DataManager.shared.currentUser != nil, StorageManager.shared.hasValidSession() else {
            StorageManager.shared.clearSession()
            UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
            alert = AppAlert(
                title: "Sign In Required",
                message: "Please sign in again before entering AirWhisper."
            )
            route = .onboarding
            return
        }

        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        NotificationCenter.default.post(name: AppState.watchConnectionStatusChangedNotification, object: nil)
        route = .main
        WatchConnectivityManager.shared.sendStoredJWTTokenIfAvailable()
    }

    /// Ported from UserProfileViewController.performSignOut().
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        if let appleId = DataManager.shared.currentUser?.appleUserIdentifier {
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleId) { _, _ in }
        }

        Task { [weak self] in
            await AuthService.logout()
            await MainActor.run {
                DataManager.shared.clearUser()
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                self?.route = .onboarding
            }
        }
    }
}
