import Foundation

struct WriteState {
    var text: String = ""
    private(set) var lastConfidence: Float = 0.0

    private let maxTextLength = 45

    mutating func appendLetter(_ letter: String, confidence: Float = 1.0) {
        guard text.count < maxTextLength else { return }
        text += letter
        lastConfidence = confidence
    }

    mutating func deleteLastLetter() {
        guard !text.isEmpty else { return }
        text.removeLast()
    }
}
