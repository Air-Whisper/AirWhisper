import SwiftUI
import UIKit

/// Visual toast component matching `MainAuthViewController.showToast` exactly.
///
/// - Dark background: RGB(0.1, 0.1, 0.1) alpha 0.85
/// - White text, system font 14pt semibold, Dynamic Type scaled
/// - Corner radius 12, clipsToBounds
/// - Centered horizontally, bottom anchored to safe area −24pt
/// - Horizontal insets ≥ 32pt from leading/trailing edges
/// - Multi-line (numberOfLines = 0)
struct ToastView: View {

    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.85)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(message)
    }
}

// MARK: - Preview

#Preview("ToastView") {
    VStack {
        Spacer()
        ToastView(message: "Password has been reset. Please sign in with your new password.")
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}