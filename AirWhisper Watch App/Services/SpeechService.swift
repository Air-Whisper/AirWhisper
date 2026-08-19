//Edited by  .
// creates a service that converts text into speech using Apple’s AVFoundation framework.
// used in actionRequiredView to speak phrase aloud.

import AVFoundation

final class SpeechService {
    
    static let shared = SpeechService()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    private init() {} // prevent creation of new objects.
    
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } // stop speaking the current speech immediately if new speech is requested while already speaking.
        
        let utterance = AVSpeechUtterance(string: trimmed) // create a speech request.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate // set the speech rate to the default value for a natural speaking pace.
        synthesizer.speak(utterance)
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }
}
