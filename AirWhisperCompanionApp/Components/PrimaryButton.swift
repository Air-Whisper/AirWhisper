import SwiftUI

/// Primary action button.
///
/// Storyboard values: height 50, background RGB(10,96,198), white title,
/// semibold 18pt font, 12pt corner radius.
struct PrimaryButton: View {

    let title: String
    var style: Style = .filled
    var height: CGFloat = 50
    var isEnabled: Bool = true
    let action: () -> Void

    enum Style {
        case filled
        case destructive
        case neutral
        case apple
    }

    private var backgroundColor: Color {
        guard isEnabled else { return Design.brandBlue.opacity(0.45) }
        switch style {
        case .filled: return Design.brandBlue
        case .destructive: return Design.destructiveRed
        case .neutral: return Design.neutralButton
        case .apple: return .black
        }
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .white }
        switch style {
        case .filled, .destructive: return .white
        case .neutral: return .black
        case .apple: return .white
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

/// Text-only link-style button ("Forgot Password?", "Resend", …).
struct TextLinkButton: View {

    let title: String
    var accentRange: String? = nil
    var fontSize: CGFloat = 14
    var alignment: TextAlignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let accentRange, let range = title.range(of: accentRange) {
                    Text(title[..<range.lowerBound]) + Text(title[range]).foregroundStyle(Design.brandBlue) + Text(title[range.upperBound...])
                } else {
                    Text(title)
                }
            }
            .font(.system(size: fontSize))
            .foregroundStyle(Design.secondaryLabel)
            .multilineTextAlignment(alignment)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
