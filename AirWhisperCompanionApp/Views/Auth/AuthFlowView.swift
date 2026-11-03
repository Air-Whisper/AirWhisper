import SwiftUI

/// Auth flow container — PLACEHOLDER for Phase 2 (real port of
/// `MainAuthViewController` + child VCs lands here).
struct AuthFlowView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Authentication")
                .font(.title2)
                .bold()
            Text("Sign in / create account — arriving in Phase 2.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.background)
    }
}
