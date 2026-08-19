import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    
    var body: some View {
        NavigationStack {
            if connectivity.companionSetupState == .ready {
                QuickSpeakView() // This is the main view of the watch app, where users can quickly access the Quick Speak feature.
            } else {
                CompanionSetupRequiredView(state: connectivity.companionSetupState) {
                    connectivity.refreshCompanionSetupState()
                }
            }
        }
        .onReceive(connectivity.$receivedVoiceGuidance) { newVoiceGuidance in
            VoiceGuidanceManager.shared.isEnabled = newVoiceGuidance
        }
        .onAppear {
            connectivity.refreshCompanionSetupState()
        }
    }
}
