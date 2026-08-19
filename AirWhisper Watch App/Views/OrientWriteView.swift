import SwiftUI

struct OrientWriteView: View {
    
    @EnvironmentObject private var connectivity: WatchConnectivityClient
    
    @State private var state = WriteState()
    @StateObject private var motionManager = OrientWriteMotionManager()
    
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var canvasSize: CGSize = CGSize(width: 150, height: 70)
    @State private var recordingSessionID: Int = 0
    
    @AppStorage("orientCursorSensitivity") private var cursorSensitivity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 4) {
            canvasArea
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .frame(height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
                .overlay(
                    Text(state.text.isEmpty ? "" : state.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                )
            
            controlButtons
        }
        .padding(.horizontal, 8)
        .onDisappear {
            cleanup()
        }
    }
    
    private var canvasArea: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 90)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
            )
            .overlay(
                GeometryReader { geometry in
                    let size = geometry.size
                    
                    ZStack {
                        if strokes.isEmpty && currentStroke.isEmpty && !motionManager.isRecording {
                            Text("Move your Wrist to Orient write")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        Canvas { context, canvasSize in
                            for stroke in strokes {
                                drawStroke(stroke, in: &context, size: canvasSize)
                            }
                            drawStroke(currentStroke, in: &context, size: canvasSize)
                        }
                        
                        cursorView(canvasSize: size)
                    }
                    .onAppear {
                        canvasSize = size
                        applySensitivitySetting()
                        motionManager.startPositioning()
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        canvasSize = newSize
                    }
                }
            )
            .onChange(of: motionManager.penPosition) { _, newPosition in
                if motionManager.isRecording {
                    currentStroke.append(newPosition)
                }
            }
            .onChange(of: motionManager.isRecording) { wasRecording, isNowRecording in
                handleRecordingChange(wasRecording: wasRecording, isNowRecording: isNowRecording)
            }
            .onChange(of: connectivity.receivedSensitivity) { _, _ in
                applySensitivitySetting()
            }
    }
    
    private func cursorView(canvasSize: CGSize) -> some View {
        let penX = motionManager.penPosition.x * canvasSize.width
        let penY = motionManager.penPosition.y * canvasSize.height
        let cursorColor: Color = motionManager.isRecording ? .green : .cyan
        
        return ZStack {
            Circle()
                .fill(cursorColor)
                .frame(width: 10, height: 10)
            
            Circle()
                .stroke(cursorColor.opacity(0.5), lineWidth: 2)
                .frame(width: 16, height: 16)
        }
        .position(x: penX, y: penY)
    }
    
    private var controlButtons: some View {
        WritingControlRow(
            isRecording: motionManager.isRecording,
            text: state.text,
            onRecordToggle: toggleRecording,
            onDelete: {
                clearCanvas()
                state.deleteLastLetter()
            }
        )
    }
    
    private func toggleRecording() {
        if motionManager.isRecording {
            let strokesToPredict = strokes + [currentStroke]
            let completedSessionID = recordingSessionID
            motionManager.stopRecording()
            predictLetter(strokes: strokesToPredict, sessionID: completedSessionID)
        } else {
            recordingSessionID += 1
            motionManager.startRecording()
        }
    }
    
    private func handleRecordingChange(wasRecording: Bool, isNowRecording: Bool) {
        if wasRecording && !isNowRecording {
            if currentStroke.count >= 2 {
                strokes.append(currentStroke)
            }
            currentStroke = []
        }
    }
    
    private func drawStroke(_ stroke: [CGPoint], in context: inout GraphicsContext, size: CGSize) {
        guard stroke.count >= 2 else { return }
        
        var path = Path()
        let firstPoint = CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height)
        path.move(to: firstPoint)
        
        for point in stroke.dropFirst() {
            let scaledPoint = CGPoint(x: point.x * size.width, y: point.y * size.height)
            path.addLine(to: scaledPoint)
        }
        
        context.stroke(path, with: .color(.white), lineWidth: 4)
    }
    
    private func clearCanvas() {
        strokes = []
        currentStroke = []
    }

    private func applySensitivitySetting() {
        if let receivedSensitivity = connectivity.receivedSensitivity {
            let clamped = max(0.0, min(100.0, Double(receivedSensitivity)))
            motionManager.sensitivityMultiplier = 0.5 + (clamped * 0.01)
        } else {
            motionManager.sensitivityMultiplier = cursorSensitivity
        }
    }
    
    private func predictLetter(strokes: [[CGPoint]], sessionID: Int) {
        let validStrokes = strokes.filter { $0.count >= 2 }
        
        guard !validStrokes.isEmpty else {
            Log.info(Log.ml, "Orient prediction skipped - no valid strokes collected")
            return
        }
        
        Log.info(Log.ml, "Orient predicting via Google API with \(validStrokes.reduce(0) { $0 + $1.count }) points from \(validStrokes.count) strokes")
        
        GoogleHandwritingService.shared.recognizeLetter(
            strokes: validStrokes,
            canvasSize: canvasSize
        ) { [self] result in
            guard sessionID == recordingSessionID, !motionManager.isRecording else {
                Log.info(Log.ml, "Dropped stale OrientWrite prediction for session \(sessionID)")
                return
            }
            
            if let letter = result {
                Log.info(Log.ml, "Google API recognized: \(letter)")
                state.appendLetter(letter, confidence: 0.85)
                VoiceGuidanceManager.shared.speak(
                    letter,
                    priority: .result,
                    interrupt: true
                )
            } else {
                Log.error(Log.ml, "Google API failed to recognize letter")
                VoiceGuidanceManager.shared.speak(
                    "Could not recognize  - please try again",
                    priority: .result,
                    interrupt: true
                )
            }
            clearCanvas()
        }
    }
    
    private func cleanup() {
        motionManager.stopTracking()
    }
}
