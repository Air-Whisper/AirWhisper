import SwiftUI
import UIKit
import WatchConnectivity

/// Watch pairing screen — full port of `WatchOnBoardingViewController`.
///
/// Used in two places:
/// - post-authentication sheet (Presented after sign-in)
/// - full-screen blocker overlay when the Watch is unpaired while in the main app
///   (ports SceneDelegate's `blockerWindow`)
struct WatchPairingView: View {

    @EnvironmentObject private var appState: AppState

    let isBlocker: Bool

    @State private var pairButtonTitle = "Pair My Watch"
    @State private var pairButtonA11yLabel = "Pair My Watch"
    @State private var pairButtonA11yValue = "Apple Watch not paired"
    @State private var pairButtonA11yHint = "Opens options to pair a watch or continue without one."

    @State private var showsAppNotInstalledAlert = false
    @State private var showsWatchNotFoundAlert = false
    @State private var showsSettingsUnavailableAlert = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Connect your Apple Watch")
                .font(.system(size: 25, weight: .bold))
                .multilineTextAlignment(.center)

            Text("AirWhisper works best with an Apple Watch. You can still manage contacts, phrases, and history without one.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                pairWatchButtonTapped()
            } label: {
                Text(pairButtonTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(Design.brandBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .accessibilityLabel(pairButtonA11yLabel)
            .accessibilityValue(pairButtonA11yValue)
            .accessibilityHint(pairButtonA11yHint)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.background)
        .onAppear { updateButtonState() }
        .onReceive(NotificationCenter.default.publisher(for: AppState.watchConnectionStatusChangedNotification)) { _ in
            updateButtonState()
        }
        .alert("Watch App Not Installed", isPresented: $showsAppNotInstalledAlert) {
            Button("Install Later") {
                UserDefaults.standard.set(true, forKey: "skipWatchPairing")
                routeToMainApp()
            }
            Button("Open Watch Settings") {
                openWatchApp()
            }
        } message: {
            Text("Please install the AirWhisper app on your Apple Watch. You can also continue and install it later.")
        }
        .alert("Apple Watch Not Found", isPresented: $showsWatchNotFoundAlert) {
            Button("Continue anyway") {
                UserDefaults.standard.set(true, forKey: "skipWatchPairing")
                routeToMainApp()
            }
            Button("Pair Watch") {
                openWatchApp()
            }
        } message: {
            Text("AirWhisper works best with an Apple Watch. You can still manage contacts, phrases, and history without one.")
        }
        .alert("Watch Settings Unavailable", isPresented: $showsSettingsUnavailableAlert) {
            Button("Continue to App") {
                UserDefaults.standard.set(true, forKey: "skipWatchPairing")
                routeToMainApp()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Unable to open Apple Watch pairing settings. You can still proceed to use the companion app.")
        }
    }

    // MARK: - updateButtonState (ported verbatim)

    private func updateButtonState() {
        guard WCSession.isSupported() else {
            pairButtonTitle = "Continue"
            pairButtonA11yLabel = "Continue to app"
            pairButtonA11yValue = "Watch connectivity unavailable"
            pairButtonA11yHint = "Continues without Apple Watch pairing."
            return
        }

        let session = WCSession.default
        if session.isPaired {
            pairButtonTitle = "Next"
            pairButtonA11yLabel = "Next"
            pairButtonA11yValue = "Apple Watch paired"
            pairButtonA11yHint = "Continues to the AirWhisper app."
        } else {
            pairButtonTitle = "Pair My Watch"
            pairButtonA11yLabel = "Pair My Watch"
            pairButtonA11yValue = "Apple Watch not paired"
            pairButtonA11yHint = "Opens options to pair a watch or continue without one."
        }
    }

    // MARK: - PairWatchButtonTapped (ported verbatim)

    private func pairWatchButtonTapped() {
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
        } else if session.isPaired && !session.isWatchAppInstalled {
            // Watch paired + app NOT installed → show option to continue or open watch settings
            showsAppNotInstalledAlert = true
        } else {
            // Watch not paired → show option to continue or pair watch
            showsWatchNotFoundAlert = true
        }
    }

    // MARK: - openWatchApp (ported verbatim)

    private func openWatchApp() {
        if let url = URL(string: "itms-watchs://") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { didOpen in
                    if !didOpen {
                        DispatchQueue.main.async {
                            showsSettingsUnavailableAlert = true
                        }
                    }
                }
            } else {
                showsSettingsUnavailableAlert = true
            }
        }
    }

    // MARK: - routeToMainApp (ported to AppState)

    private func routeToMainApp() {
        appState.completeWatchOnboarding()
    }
}
