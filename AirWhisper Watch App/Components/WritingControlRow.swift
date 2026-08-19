import SwiftUI

struct WritingControlRow: View {
    let isRecording: Bool
    let text: String
    let onRecordToggle: () -> Void
    let onDelete: () -> Void
    
    @AccessibilityFocusState private var focusedElement: FocusElement?
    
    enum FocusElement: Hashable {
        case recordToggle
        case delete
        case done
    }
    
    var body: some View {
        HStack(spacing: 8) {
            ActionButton(
                title: isRecording ? "Stop" : "Start",
                style: isRecording ? .destructive : .primary
            ) {
                VoiceGuidanceManager.shared.speak(
                    isRecording ? "Stop Recording" : "Start Recording",
                    priority: .action,
                    interrupt: true
                )
                onRecordToggle()
            }
            .layoutPriority(1)
            .accessibilityLabel(isRecording ? "Stop Button" : "Start Button")
            .accessibilityFocused($focusedElement, equals: .recordToggle)
            
            Button {
                onDelete()
            } label: {
                ActionButton(icon: "delete.left", style: .secondary)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty)
            .frame(width: 50)
            .accessibilityLabel("Delete Character")
            .accessibilityFocused($focusedElement, equals: .delete)
            
            NavigationLink {
                ActionRequiredView(text: text)
            } label: {
                ActionButton(title: "Done", style: .secondary)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .disabled(text.isEmpty)
            .accessibilityLabel("Done")
            .accessibilityFocused($focusedElement, equals: .done)
        }
        .frame(height: 50)
        .onChange(of: focusedElement) { _, newValue in
            switch newValue {
            case .recordToggle:
                VoiceGuidanceManager.shared.speak(
                    isRecording ? "Stop Button" : "Start Button",
                    priority: .focus,
                    interrupt: false
                )
            case .delete:
                VoiceGuidanceManager.shared.speak(
                    "Delete Character",
                    priority: .focus,
                    interrupt: false
                )
            case .done:
                VoiceGuidanceManager.shared.speak(
                    "Done",
                    priority: .focus,
                    interrupt: false
                )
            case .none:
                break
            }
        }
    }
}
