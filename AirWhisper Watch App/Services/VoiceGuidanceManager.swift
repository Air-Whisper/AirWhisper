import Foundation
import AVFoundation
import SwiftUI
import Combine

// Manages the custom voice guidance feature using AVSpeechSynthesizer.
// This acts as a lighter, app-specific alternative to VoiceOver, speaking
// the names of focused UI elements or recognized letters.
final class VoiceGuidanceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Priority: Int {
        case focus
        case action
        case result
    }
    
    // Shared singleton instance
    static let shared = VoiceGuidanceManager()
    
    // Toggle state, persisted in UserDefaults
    @Published var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            
            UserDefaults.standard.set(isEnabled, forKey: "isVoiceGuidanceEnabled")
            // When toggled on, we need to ensure the audio session is ready
            if isEnabled {
                configureAudioSession()
                speak("Voice guidance enabled")
            } else {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }
    
    private let synthesizer = AVSpeechSynthesizer()
    private var isAudioSessionConfigured = false
    private var currentPriority: Priority?
    private var currentText: String?
    private var lastSpokenText: String?
    private var lastSpokenAt: Date = .distantPast
    private let duplicateSuppressionWindow: TimeInterval = 0.35
    
    private override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "isVoiceGuidanceEnabled")
        super.init()
        synthesizer.delegate = self
        if isEnabled {
            configureAudioSession()
        }
    }
    
    /// Configures the AVAudioSession for playback so the Watch speaker can be used.
    private func configureAudioSession() {
        guard !isAudioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            isAudioSessionConfigured = true
        } catch {
            print("VoiceGuidanceManager: Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /// Speaks the given text if voice guidance is enabled.
    /// Cancels any currently speaking text immediately.
    func speak(_ text: String, priority: Priority = .action, interrupt: Bool? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.speak(text, priority: priority, interrupt: interrupt)
            }
            return
        }

        guard isEnabled else { return }
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let now = Date()
        if lastSpokenText == trimmed, now.timeIntervalSince(lastSpokenAt) < duplicateSuppressionWindow {
            return
        }
        
        let shouldInterrupt = interrupt ?? (priority.rawValue >= (currentPriority?.rawValue ?? Priority.focus.rawValue))
        
        if synthesizer.isSpeaking {
            let activePriority = currentPriority ?? .focus
            if priority.rawValue < activePriority.rawValue {
                return
            }
            
            if priority.rawValue == activePriority.rawValue, shouldInterrupt == false {
                return
            }
            
            if currentText == trimmed {
                return
            }
            
            if shouldInterrupt {
                synthesizer.stopSpeaking(at: .immediate)
            } else {
                return
            }
        }
        
        let utterance = AVSpeechUtterance(string: trimmed)
        // Rate range is 0.0 to 1.0 (default is 0.5)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        
        // Optional: you can pick a specific language/voice here if desired
        // utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        currentPriority = priority
        currentText = trimmed
        lastSpokenText = trimmed
        lastSpokenAt = now
        synthesizer.speak(utterance)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.clearCurrentSpeechState()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.clearCurrentSpeechState()
        }
    }
    
    private func clearCurrentSpeechState() {
        currentPriority = nil
        currentText = nil
    }
}
