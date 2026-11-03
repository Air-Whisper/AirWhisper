import SwiftUI

/// Main app tab container — PLACEHOLDER for Phase 3 (Home, Quick Speak,
/// Contacts, History, Profile land here).
struct MainTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("AirWhisper")
                .font(.title2)
                .bold()
            Text("Main tabs — arriving in Phase 3.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.background)
    }
}
