import SwiftUI

struct ProfileInfoRow: View {
    let title: String
    let value: String
    let valueColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 17))

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Design.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
