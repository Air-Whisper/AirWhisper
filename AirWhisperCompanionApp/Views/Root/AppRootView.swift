import SwiftUI

/// Root view: routes between onboarding / auth / watch pairing / main app and
/// draws the watch-disconnect blocker overlay.
///
/// Ports the rootViewController swaps from SceneDelegate and the blocker
/// window (`blockerWindow` at `.alert + 1` level).
struct AppRootView: View {

    @EnvironmentObject private var appState: AppState
    @State private var isWatchPairingSheetPresented = false

    var body: some View {
        ZStack {
            content

            if appState.isWatchBlockerVisible {
                // The blocker window showed the WatchOnBoarding view controller
                // above everything else when the watch is unpaired.
                WatchPairingView(isBlocker: true)
                    .environmentObject(appState)
            }
        }
        .alert(item: $appState.alert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: appState.route) { _, newRoute in
            isWatchPairingSheetPresented = (newRoute == .watchPairing)
        }
        .sheet(isPresented: $isWatchPairingSheetPresented) {
            WatchPairingView(isBlocker: false)
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true) // isModalInPresentation = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.route {
        case .onboarding:
            OnboardingView()
                .environmentObject(appState)

        case .auth:
            AuthFlowView()
                .environmentObject(appState)

        case .watchPairing:
            // Presented as a sheet above the auth flow (see .sheet above).
            EmptyView()

        case .main:
            MainTabView()
                .environmentObject(appState)
        }
    }
}
