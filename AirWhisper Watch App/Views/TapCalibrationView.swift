import SwiftUI
import WatchKit

struct TapCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var detector = SurfaceTapDetector.shared
    
    @State private var currentSample: Int = 1
    @State private var totalSamples: Int = 3
    @State private var phaseTitle = "Phase 1: Single Taps"
    @State private var instructionText = "Record your single tap 3 times."
    
    var body: some View {
        VStack(spacing: 12) {
            
            Text(phaseTitle)
                .font(.caption)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.top, instructionText.isEmpty ? 16 : 0)
            if !instructionText.isEmpty {
                Text(instructionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)
            }
            
            Spacer()
            
            if !detector.isCalibrating && detector.isCalibrated && detector.calibrationPhase == .idle {
                // Done State
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                
            } else {
                // Recording State
                if detector.isRecordingTap {
                    Button("Stop recording", systemImage: "stop.fill") {
                        detector.stopRecordingTap()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityHint("Stops recording the current tap sample.")
                    // .pulse() effect using an overlay
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 30)
//                            .stroke(Color.red, lineWidth: 2)
//                            .scaleEffect(1.1)
//                            .opacity(0.5)
//                            .animation(.easeInOut(duration: 1).repeatForever(), value: detector.isRecordingTap)
//                    )
                } else {
                    Button("Record tap sample", systemImage: "record.circle") {
                        detector.startRecordingTap()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityHint("Starts recording tap sample \(currentSample) of \(totalSamples).")
                }
            }
        }
        .padding(.horizontal, 8)
        .navigationTitle("Calibrate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupCalibration()
        }
        .onDisappear {
            if detector.isCalibrating {
                detector.cancelCalibration()
            }
        }
    }
    
    private func setupCalibration() {
        currentSample = 1
        totalSamples = 3
        phaseTitle = "Single Taps"
        instructionText = "Recording \(currentSample)/\(totalSamples)"
        
        VoiceGuidanceManager.shared.speak("Press Record, perform one single tap, then press Stop. Do this 3 times.")
        
        detector.onPhaseChange = { phase in
            if phase == .doubleTaps {
                currentSample = 1
                phaseTitle = "Double Taps"
                instructionText = "Recording \(currentSample)/\(totalSamples)"
                VoiceGuidanceManager.shared.speak("Great. Now press Record, perform one double tap, then press Stop. Do this 3 times.")
            }
        }
        
        detector.onCalibrationSampleComplete = { sampleNumber, total in
            currentSample = sampleNumber + 1
            if currentSample <= total {
                instructionText = "Recording \(currentSample)/\(totalSamples)"
                VoiceGuidanceManager.shared.speak("Sample recorded. \(total - sampleNumber) left.")
            }
        }
        
        detector.onCalibrationFinalComplete = {
            instructionText = ""
            phaseTitle = "Calibration complete!"
            VoiceGuidanceManager.shared.speak("Calibration complete! You're all set.")
        }
        
        detector.startCalibration()
    }
}
