// defines the quick speak view, which displays a list of phrases and writing modes.
// main view of the watch app, allowing users to quickly select a phrase to speak or access different writing modes for inputting custom phrases.
import SwiftUI

struct QuickSpeakView: View {
    
    @ObservedObject private var phraseManager = PhraseManager.shared
    @ObservedObject private var connectivity = WatchConnectivityClient.shared
    
    @State private var focusedIndex: Int = 0
    @State private var showCalibration = false
    @State private var navigateToPhrase: PhraseRoute? = nil
    
    @AccessibilityFocusState private var focusedElement: FocusElement?
    
    enum FocusElement: Hashable {
        case phrase(String)
        case airWrite
        case orientWrite
    }

    private struct PhraseRoute: Identifiable, Hashable {
        let id = UUID()
        let text: String
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                let phrases = phraseManager.allPhrases

                // creating a phrase button for each element in the phrases array
                ForEach(phrases.indices, id: \.self) { index in
                    let phrase = phrases[index]

                    PhraseButton(title: phrase)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(connectivity.receivedTapDetectorEnabled && focusedIndex == index ? Color.green : Color.clear, lineWidth: 4)
                        )
                        .accessibilityLabel(phrase)
                        .accessibilityFocused($focusedElement, equals: .phrase(phrase))
                }
                
                if !connectivity.receivedTapDetectorEnabled {
                    Divider().padding(.vertical, 6)
                    
                    HStack {
                        Text("Writing Modes")
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                    }

                    NavigationLink {
                        AirWriteView()
                    } label: {
                        LargeActionButton(title: "Air Write", icon: "hand.wave")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Air Write")
                    .accessibilityFocused($focusedElement, equals: .airWrite)

                    NavigationLink {
                        OrientWriteView()
                    } label: {
                        LargeActionButton(title: "Orient Write", icon: "pencil.tip")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Orient Write")
                    .accessibilityFocused($focusedElement, equals: .orientWrite)
                }
            }
            .padding()
        }
        .navigationTitle("Quick Speak")
        .navigationDestination(isPresented: $showCalibration) {
            TapCalibrationView()
        }
        .navigationDestination(item: $navigateToPhrase) { route in
            ActionRequiredView(text: route.text, isFromQuickPhrase: true)
        }
        .onChange(of: focusedElement) { _, newValue in
            switch newValue {
            case .phrase(let text):
                VoiceGuidanceManager.shared.speak(text)
            case .airWrite:
                VoiceGuidanceManager.shared.speak("Air Write")
            case .orientWrite:
                VoiceGuidanceManager.shared.speak("Orient Write")
            case .none:
                break
            }
        }
        .onAppear {
            setupTapDetector()
        }
        .onDisappear {
            SurfaceTapDetector.shared.stop(for: "QuickSpeakView")
        }
        .onChange(of: connectivity.receivedTapDetectorEnabled) { _, _ in
            setupTapDetector()
        }
        .onChange(of: phraseManager.allPhrases) { _, phrases in
            resetFocusedPhrase(using: phrases, speakCurrent: connectivity.receivedTapDetectorEnabled)
        }
        .onChange(of: showCalibration) { _, isShowing in
            if !isShowing {
                setupTapDetector()
            }
        }
    }
    
    private func setupTapDetector() {
        if connectivity.receivedTapDetectorEnabled {
            // Check if calibration is needed before starting detection
            guard SurfaceTapDetector.shared.isCalibrated else {
                showCalibration = true
                return
            }
            
            focusedIndex = 0
            
            // Speak first item immediately when entering mode if phrases exist
            resetFocusedPhrase(using: phraseManager.allPhrases, speakCurrent: true)
            
            SurfaceTapDetector.shared.onSingleTap = {
                let phrases = phraseManager.allPhrases
                if let phrase = advanceFocusedPhrase(using: phrases) {
                    VoiceGuidanceManager.shared.speak(phrase)
                }
            }
            
            SurfaceTapDetector.shared.onDoubleTap = {
                let phrases = phraseManager.allPhrases
                if let phrase = focusedPhrase(using: phrases) {
                    navigateToPhrase = PhraseRoute(text: phrase)
                }
            }
            SurfaceTapDetector.shared.start(for: "QuickSpeakView")
        } else {
            SurfaceTapDetector.shared.stop(for: "QuickSpeakView")
        }
    }

    private func resetFocusedPhrase(using phrases: [String], speakCurrent: Bool = false) {
        focusedIndex = 0
        guard let first = phrases.first else { return }

        if speakCurrent {
            VoiceGuidanceManager.shared.speak(first)
        }
    }

    private func advanceFocusedPhrase(using phrases: [String]) -> String? {
        guard !phrases.isEmpty else {
            focusedIndex = 0
            return nil
        }

        if phrases.indices.contains(focusedIndex) {
            focusedIndex = (focusedIndex + 1) % phrases.count
        } else {
            focusedIndex = 0
        }

        return phrases[focusedIndex]
    }

    private func focusedPhrase(using phrases: [String]) -> String? {
        guard !phrases.isEmpty else {
            focusedIndex = 0
            return nil
        }

        if !phrases.indices.contains(focusedIndex) {
            focusedIndex = 0
        }

        return phrases[focusedIndex]
    }
}
