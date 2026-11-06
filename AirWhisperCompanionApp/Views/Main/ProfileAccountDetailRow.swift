import SwiftUI

struct ProfileAccountDetailRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)

            Spacer(minLength: 6)

            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
