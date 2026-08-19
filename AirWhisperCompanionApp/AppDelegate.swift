import UIKit
import GoogleSignIn

@main // start point of the iphone app
class AppDelegate: UIResponder, UIApplicationDelegate {
// using UIResponder to allow objects to respond to events, and UIApplicationDelegate to manage the application's lifecycle, launch/backgrounding/termination.

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // didFinishLaunchingWithOptions with launchOptions set to anything means this method is called when the app finishes launching, and it can handle any launch options (like notifications, etc.)
        WatchConnectivityManager.shared.activateSession()
        // activateSession is called to set up the communication session with the Apple Watch, allowing the app to send and receive data from the watch.

        // Configure Google Sign-In using the client ID from Info.plist.
        // GIDSignIn.sharedInstance.configuration is set here once at launch so all
        // subsequent GIDSignIn calls throughout the app know which OAuth client to use.
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        return true
        // give true only when succesful launch
    }



    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // allowing the app to have multiple scenes with options set to handle launches from urls, notifications, etc.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        // creating a new scene config with default name which matches the one in the Info.plist file, and using the role of the connecting scene session to determine how the scene should be configured.
        // connectingSceneSession is set to role as the system will determine the role of the scene (like windowed, external display) and configure it accordingly.
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
    // this method is called when the user discards a scene session, allowing the app to release any resources specific to the discarded scenes, as they will not return improving memeory util.

}
