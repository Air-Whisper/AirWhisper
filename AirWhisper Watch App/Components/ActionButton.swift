//Edited by   on 2024-06-16.
// To define button components used throughout the watch app
import SwiftUI

enum ButtonStyle {
    case primary, secondary, destructive
    
    var color: Color {
        switch self {
        case .primary: return .green.opacity(0.3)
        case .secondary: return .gray.opacity(0.2)
        case .destructive: return .red.opacity(0.3)
        }
    }
}

struct ActionButton: View {
    let title: String?
    let icon: String?
    let style: ButtonStyle
    let action: (() -> Void)?
    
    init(title: String, style: ButtonStyle = .secondary, action: @escaping () -> Void) {
        self.title = title; self.icon = nil; self.style = style; self.action = action
    }
    
    init(icon: String, style: ButtonStyle = .secondary, action: @escaping () -> Void) {
        self.title = nil; self.icon = icon; self.style = style; self.action = action
    }
    
    init(title: String, style: ButtonStyle = .secondary) {
        self.title = title; self.icon = nil; self.style = style; self.action = nil
    }
    
    init(icon: String, style: ButtonStyle = .secondary) {
        self.title = nil; self.icon = icon; self.style = style; self.action = nil
    }
    
    var body: some View {
        Group {
            if let action { Button(action: action) { content } }
            else { content }
        }
        .buttonStyle(.plain)
    }
    
    private var content: some View {
        Group {
            if let title {
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let icon {
                Image(systemName: icon)
                    .font(.title3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .background(style.color)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .glassEffect(in: .rect(cornerRadius: 14))
    }
}

struct LargeActionButton: View {
    let title: String
    let icon: String?
    let color: Color
    let action: (() -> Void)?
    
    init(title: String, icon: String? = nil, color: Color = .gray.opacity(0.2), action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    init(title: String, icon: String? = nil, color: Color = .gray.opacity(0.2)) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = nil
    }
    
    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
            } else {
                content
            }
        }
        .buttonStyle(.plain)
    }
    
    private var content: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .glassEffect(in: .rect(cornerRadius: 10))
    }
}
