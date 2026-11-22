import SwiftUI
import GoogleSignIn

/// App entry point.
///
/// Ports the startup behavior previously living in:
/// - `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
/// - `SceneDelegate.scene(_:willConnectTo:)`
/// - `SceneDelegate.scene(_:openURLContexts:)`
/// - `SceneDelegate.sceneDidBecomeActive(_:)`
@main
struct AirWhisperApp: App {

    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // From AppDelegate.application(_:didFinishLaunchingWithOptions:)
        WatchConnectivityManager.shared.activateSession()

        // Configure Google Sign-In using the client ID from Info.plist.
        // GIDSignIn.sharedInstance.configuration is set here once at launch so
        // all subsequent GIDSignIn calls throughout the app know which OAuth
        // client to use.
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        // From SceneDelegate.scene(_:willConnectTo:): cloud sync + launch routing.
        appState.handleLaunch()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    // From SceneDelegate.scene(_:openURLContexts:)
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    // From SceneDelegate.sceneDidBecomeActive(_:)
                    if phase == .active {
                        appState.handleSceneActive()
                    }
                }
        }
    }
}
