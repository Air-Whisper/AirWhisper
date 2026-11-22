import AVFoundation

/// Which audio session configuration a spoken utterance should use.
enum SpeechAudioMode {
    case guidance
    case phrase
}

/// Selects the shared AVAudioSession configuration before each kind of speech.
///
/// - `.guidance` uses `.playAndRecord` with no Bluetooth options, so an A2DP
///   speaker is not an eligible output and guidance should stay on the Watch
///   speaker.
/// - `.phrase` uses `.playback`, which permits A2DP output for "Speak Aloud".
///
/// This only changes which outputs are *eligible*; it cannot name a specific
/// device, and it changes the route for the whole app. The two kinds of speech
/// must therefore never overlap. Needs validation on a physical Watch.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private var currentMode: SpeechAudioMode?

    private init() {}

    func configure(for mode: SpeechAudioMode) {
        let session = AVAudioSession.sharedInstance()

        do {
            if currentMode != mode {
                switch mode {
                case .guidance:
                    // Deliberately no .allowBluetoothA2DP / .allowBluetooth(HFP).
                    try session.setCategory(
                        .playAndRecord,
                        mode: .voicePrompt,
                        options: .duckOthers
                    )
                case .phrase:
                    try session.setCategory(
                        .playback,
                        mode: .voicePrompt,
                        options: .duckOthers
                    )
                }
                currentMode = mode
            }

            try session.setActive(true)
        } catch {
            currentMode = nil
            print("AudioSessionManager: failed to configure for \(mode): \(error.localizedDescription)")
        }
    }
}
