import SwiftUI

struct AirWriteView: View {
    
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    @EnvironmentObject private var modelState: MLModelState
    
    @State private var state = WriteState()
    @StateObject private var recorder = AirWriteMotionRecorder()
    private let appendConfidenceThreshold: Double = 0.50
    
    var body: some View
    {
        VStack(spacing: 6)
        {
            if !modelState.isReady
            {
                // Model is still warming up  - show a loading indicator
                Spacer()
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Loading Model")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Spacer()
            } else {
                TextDisplayBox(
                    text: state.text,
                    placeholder: "Move your hand\nto Air write"
                )
                
                controlButtons
            }
        }
        .padding(.horizontal, 8)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupRecorder()
        }
        .onDisappear
        {
            cleanup()
        }
    }
    
    private var controlButtons: some View {
        WritingControlRow(
            isRecording: recorder.isRecording,
            text: state.text,
            onRecordToggle: toggleRecording,
            onDelete: { state.deleteLastLetter() }
        )
    }
    
    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
    }
    
    private func setupRecorder() { // This sets up the motion recorder and defines what happens when a letter is completed.
        recorder.onLetterComplete = { sessionID, samples in
            DispatchQueue.main.async {
                guard sessionID == recorder.currentSessionID, !recorder.isRecording else {
                    Log.info(Log.ml, "Dropped stale AirWrite prediction for session \(sessionID)")
                    return
                }
                processSamples(samples)
            }
        }
    }
    
    private func cleanup() { // This ensures that if the user navigates away while recording, we stop the recording to prevent resource leaks and unintended behavior.
        if recorder.isRecording {
            recorder.stopRecording()
        }
    }
    
    private func processSamples(_ samples: [MotionSample]) {
        guard !samples.isEmpty else { return }
        
        let processed = AirWritePreprocessor.preprocessWithDiagnostics(samples)

        let d = processed.diagnostics
        Log.debug(
            Log.preprocess,
            "diag raw=\(d.rawCount) stage2=\(d.afterStage2Count) stage3=\(d.afterStage3Count) stage6=\(d.afterStage6Count) stage8=\(d.afterStage8Count) shape=\(d.stage11Shape.rows)x\(d.stage11Shape.cols)"
        )

        do {
            let prediction = try AirWriteMLRunner.predictDetailed(processed.tensor)
            let top3 = prediction.top3
                .map { "\($0.label):\(String(format: "%.3f", $0.prob))" }
                .joined(separator: ",")
            Log.debug(
                Log.ml,
                "viewPrediction main=\(prediction.mainLabel) final=\(prediction.finalLabel) dp=\(prediction.dpProb.map { String(format: "%.3f", $0) } ?? "nil") refined=\(prediction.dpRefined ? 1 : 0) top3=[\(top3)]"
            )
            if prediction.confidence >= appendConfidenceThreshold {
                state.appendLetter(prediction.finalLabel, confidence: Float(prediction.confidence))
                VoiceGuidanceManager.shared.speak(
                    prediction.finalLabel,
                    priority: .result,
                    interrupt: true
                )
            } else {
                Log.info(
                    Log.ml,
                    String(
                        format: "Dropped low-confidence prediction final=%@ conf=%.4f threshold=%.2f",
                        prediction.finalLabel,
                        prediction.confidence,
                        appendConfidenceThreshold
                    )
                )
            }
        } catch {
            Log.error(Log.ml, "Prediction failed: \(error.localizedDescription)")
        }
    }
}
