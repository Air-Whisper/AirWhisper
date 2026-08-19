import SwiftUI
struct ActionRequiredView: View // Displays actions after a user composes text via AirWrite or OrientWrite, allowing users to speak it aloud, send it to contacts, or save it as a quick phrase.
{
    let text: String //Receives text from WritingControlRow
    
    var isFromQuickPhrase: Bool = false
    
    @State private var showingSaveConfirmation = false
    @State private var phraseAlreadyExists = false
    @State private var showingReplacedConfirmation = false

    @ObservedObject private var connectivity = WatchConnectivityClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var focusedIndex: Int = 0
    @State private var navigateToContactSelect: Bool = false
    /// Tracks whether the user performed an action so we can call markPhraseUsed
    /// only after this view disappears  - preventing mid-navigation phrase reordering.
    @State private var actionPerformed: Bool = false
    
    private var actionElements: [String] {
        var elements = ["Speak Aloud", "Send To"]
        if !isFromQuickPhrase { elements.append("Save as Phrase") }
        elements.append("Cancel")
        return elements
    }

    @AccessibilityFocusState private var focusedElement: FocusElement?
    
    enum FocusElement: Hashable {
        case speakAloud
        case sendTo
        case saveAsPhrase
    }

    var body: some View 
    {
        ScrollView 
        {
            VStack(spacing: 12) 
            {
                Text(text) //Shows the composed text at the top of the view.
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 8)

                LargeActionButton(
                    title: "Speak Aloud",
                    icon: "speaker.wave.2",
                    color: .green.opacity(0.3)
                ) 
                {
                    executeSpeakAloud()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(connectivity.receivedTapDetectorEnabled && focusedIndex == 0 ? Color.green : Color.clear, lineWidth: 4)
                )
                .accessibilityLabel("Speak Aloud")
                .accessibilityFocused($focusedElement, equals: .speakAloud)
                
                LargeActionButton(title: "Send To", icon: "paperplane") {
                    if isFromQuickPhrase { actionPerformed = true }
                    navigateToContactSelect = true
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(connectivity.receivedTapDetectorEnabled && focusedIndex == 1 ? Color.green : Color.clear, lineWidth: 4)
                )
                .buttonStyle(.plain)
                .accessibilityLabel("Send To")
                .accessibilityFocused($focusedElement, equals: .sendTo)
                if !isFromQuickPhrase 
                {
                    LargeActionButton(title: "Save as Phrase", icon: "bookmark") 
                    {
                        saveAsPhrase()
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(connectivity.receivedTapDetectorEnabled && focusedIndex == 2 ? Color.green : Color.clear, lineWidth: 4)
                    )
                    .accessibilityLabel("Save as Phrase")
                    .accessibilityFocused($focusedElement, equals: .saveAsPhrase)
                }
                
                let cancelIndex = isFromQuickPhrase ? 2 : 3
                LargeActionButton(title: "Cancel", icon: "xmark.circle", color: .red.opacity(0.3)) {
                    dismiss()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(connectivity.receivedTapDetectorEnabled && focusedIndex == cancelIndex ? Color.green : Color.clear, lineWidth: 4)
                )
            }
            .padding()
        }
        .navigationTitle("Actions")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToContactSelect) {
            ContactSelectView(messageText: text, isFromQuickPhrase: isFromQuickPhrase)
        }
        .onChange(of: focusedElement) { _, newValue in
            switch newValue {
            case .speakAloud: VoiceGuidanceManager.shared.speak("Speak Aloud")
            case .sendTo: VoiceGuidanceManager.shared.speak("Send To Contact")
            case .saveAsPhrase: VoiceGuidanceManager.shared.speak("Save as Phrase")
            case .none: break
            }
        }
        .onAppear {
            setupTapDetector()
        }
        .onDisappear {
            SurfaceTapDetector.shared.stop(for: "ActionRequiredView")
            // Defer markPhraseUsed to after the view is gone so the reorder
            // does not affect anything while this screen is still visible.
            if isFromQuickPhrase && actionPerformed {
                PhraseManager.shared.markPhraseUsed(text)
            }
        }
        .onChange(of: connectivity.receivedTapDetectorEnabled) { _, _ in
            setupTapDetector()
        }
        .alert("Phrase Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("'\(text)' has been added to Quick Speak.")
        }
        .alert("Phrase Replaced", isPresented: $showingReplacedConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Quick Speak is full (max \(PhraseManager.maxPhrases)). The least-used phrase was replaced with '\(text)'.")
        }
        .alert("Already Exists", isPresented: $phraseAlreadyExists) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This phrase is already in your Quick Speak list.")
        }
    }

    private func executeSpeakAloud() {
        SpeechService.shared.speak(text)
        if isFromQuickPhrase {
            // Do NOT call markPhraseUsed here  - defer to onDisappear to avoid
            // phrase reordering while the action screen is still on screen.
            actionPerformed = true
        }
    }
    
    private func setupTapDetector() {
        if connectivity.receivedTapDetectorEnabled {
            focusedIndex = 0
            
            if !actionElements.isEmpty {
                VoiceGuidanceManager.shared.speak(actionElements[0])
            }
            
            SurfaceTapDetector.shared.onSingleTap = {
                let total = actionElements.count
                if total > 0 {
                    focusedIndex = (focusedIndex + 1) % total
                    VoiceGuidanceManager.shared.speak(actionElements[focusedIndex])
                }
            }
            
            SurfaceTapDetector.shared.onDoubleTap = {
                executeAction(at: focusedIndex)
            }
            SurfaceTapDetector.shared.start(for: "ActionRequiredView")
        } else {
            SurfaceTapDetector.shared.stop(for: "ActionRequiredView")
        }
    }
    
    private func executeAction(at index: Int) {
        guard index >= 0 && index < actionElements.count else { return }
        let element = actionElements[index]
        switch element {
        case "Speak Aloud":
            executeSpeakAloud()
        case "Send To":
            if isFromQuickPhrase { actionPerformed = true }
            navigateToContactSelect = true
        case "Save as Phrase":
            saveAsPhrase()
        case "Cancel":
            dismiss()
        default:
            break
        }
    }

    private func saveAsPhrase() 
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let wasFull = PhraseManager.shared.phrases.count >= PhraseManager.maxPhrases
        let added = PhraseManager.shared.addPhrase(trimmed)
        if added 
        {
            if wasFull 
            {
                showingReplacedConfirmation = true
            } 
            else 
            {
                showingSaveConfirmation = true
            }
        }
        else 
        {
            phraseAlreadyExists = true
        }
    }
}
