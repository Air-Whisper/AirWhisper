import SwiftUI
// this is a simple view that shows the text that the user has written in the air and a placeholder if there is no text.
struct TextDisplayBox: View {
    
    let text: String
    let placeholder: String 
    var height: CGFloat = 90
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            )
            .overlay(
                VStack(spacing: 4) {
                    if text.isEmpty {
                        ForEach(placeholder.components(separatedBy: "\n"), id: \.self) { line in
                            Text(line)
                                .font(.footnote.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(text)
                            .font(.title3.weight(.medium))
                            .lineLimit(4)
                            .minimumScaleFactor(0.5)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
            )
    }
}