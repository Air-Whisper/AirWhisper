import Foundation
import CoreMotion
import Combine
import WatchKit

private enum SurfaceTapMotionEvent: Sendable {
    case validatedTap(timeSincePrevious: TimeInterval)
}

private final class SurfaceTapMotionProcessor: @unchecked Sendable {
    private let lock = NSLock()

    private var downwardThreshold: Double = -0.5
    private var upwardThreshold: Double = 0.2

    private let debounceInterval: TimeInterval = 0.2
    private var lastDownwardSpikeTime: Date?
    private var lastValidatedTapTime: Date?

    private var isCalibrating = false
    private var isRecordingTap = false
    private var recordingBuffer: [Double] = []

    func updateThresholds(down: Double, up: Double) {
        withLock {
            downwardThreshold = down
            upwardThreshold = up
        }
    }

    func resetDetection() {
        withLock {
            lastDownwardSpikeTime = nil
            lastValidatedTapTime = nil
        }
    }

    func setCalibrating(_ calibrating: Bool) {
        withLock {
            isCalibrating = calibrating
            if !calibrating {
                isRecordingTap = false
                recordingBuffer.removeAll(keepingCapacity: true)
            }
        }
    }

    func startRecordingTap() {
        withLock {
            recordingBuffer.removeAll(keepingCapacity: true)
            isRecordingTap = true
        }
    }

    func stopRecordingTap() -> [Double] {
        withLock {
            isRecordingTap = false
            let samples = recordingBuffer
            recordingBuffer.removeAll(keepingCapacity: true)
            return samples
        }
    }

    func cancelRecording() {
        withLock {
            isRecordingTap = false
            recordingBuffer.removeAll(keepingCapacity: true)
        }
    }

    func process(z: Double, at now: Date) -> SurfaceTapMotionEvent? {
        withLock {
            if isRecordingTap {
                recordingBuffer.append(z)
                return nil
            }

            guard !isCalibrating else { return nil }

            if z <= downwardThreshold {
                lastDownwardSpikeTime = now
                return nil
            }

            guard z >= upwardThreshold, let downTime = lastDownwardSpikeTime else {
                return nil
            }

            let timeSinceDown = now.timeIntervalSince(downTime)
            guard timeSinceDown < 0.25 else { return nil }

            lastDownwardSpikeTime = nil

            if let last = lastValidatedTapTime, now.timeIntervalSince(last) < debounceInterval {
                return nil
            }

            let timeSincePrevious = lastValidatedTapTime.map { now.timeIntervalSince($0) } ?? Double.greatestFiniteMagnitude
            lastValidatedTapTime = now

            return .validatedTap(timeSincePrevious: timeSincePrevious)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
final class SurfaceTapDetector: ObservableObject {
    static let shared = SurfaceTapDetector()

    @Published private(set) var isCalibrated: Bool = false

    private var downwardThreshold: Double = -0.5
    private var upwardThreshold: Double = 0.2
    private var doubleTapTiming: TimeInterval = 0.4

    private let requiredSamplesPerPhase = 3
    private let doubleTapTolerance: TimeInterval = 0.25

    enum CalibrationPhase {
        case idle
        case singleTaps
        case doubleTaps
    }

    @Published private(set) var calibrationPhase: CalibrationPhase = .idle
    @Published private(set) var isRecordingTap: Bool = false
    @Published private(set) var isCalibrating = false

    private var collectedDownwardPeaks: [Double] = []
    private var collectedUpwardPeaks: [Double] = []
    private var collectedDoubleTapTimings: [TimeInterval] = []

    private var tapCount = 0
    private var singleTapTask: Task<Void, Never>?

    var onSingleTap: (@MainActor () -> Void)?
    var onDoubleTap: (@MainActor () -> Void)?
    var onCalibrationSampleComplete: (@MainActor (Int, Int) -> Void)?
    var onPhaseChange: (@MainActor (CalibrationPhase) -> Void)?
    var onCalibrationFinalComplete: (@MainActor () -> Void)?

    private let motionManager = CMMotionManager()
    private let processor = SurfaceTapMotionProcessor()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.airwhisper.surfacetap.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private var activeIdentifier: String?
    @Published private(set) var isActive = false

    private init() {
        loadCalibrationSettings()
    }

    func start(for identifier: String) {
        activeIdentifier = identifier
        guard !isActive else { return }
        isActive = true
        loadCalibrationSettings()
        processor.setCalibrating(false)
        processor.resetDetection()
        startMotionUpdates()
        Log.debug(Log.motion, "[SurfaceTapDetector] Started for \(identifier)  - calibrated: \(isCalibrated)")
        Log.debug(Log.motion, "[SurfaceTapDetector] Thresholds -> Down: \(downwardThreshold), Up: \(upwardThreshold), DTTiming: \(doubleTapTiming)")
    }

    func stop(for identifier: String) {
        guard activeIdentifier == identifier else { return }
        guard isActive else { return }
        isActive = false
        activeIdentifier = nil
        motionManager.stopDeviceMotionUpdates()
        cancelPendingTap()
        processor.setCalibrating(false)
        Log.info(Log.motion, "[SurfaceTapDetector] Stopped")
    }

    func startCalibration() {
        cancelPendingTap()
        isCalibrating = true
        calibrationPhase = .singleTaps
        isRecordingTap = false
        collectedDownwardPeaks.removeAll()
        collectedUpwardPeaks.removeAll()
        collectedDoubleTapTimings.removeAll()

        processor.setCalibrating(true)
        processor.cancelRecording()
        processor.resetDetection()
        startMotionUpdates()
        Log.info(Log.motion, "[SurfaceTapDetector] Calibration activated - Phase 1 (Single Taps)")
    }

    func cancelCalibration() {
        isCalibrating = false
        isRecordingTap = false
        calibrationPhase = .idle
        processor.setCalibrating(false)
        processor.cancelRecording()
        cancelPendingTap()
        motionManager.stopDeviceMotionUpdates()
    }

    func resetCalibration() {
        UserDefaults.standard.removeObject(forKey: "STDownwardThreshold")
        UserDefaults.standard.removeObject(forKey: "STUpwardThreshold")
        UserDefaults.standard.removeObject(forKey: "STDoubleTapTiming")
        loadCalibrationSettings()
    }

    func startRecordingTap() {
        guard isCalibrating else { return }
        processor.startRecordingTap()
        isRecordingTap = true
        WKInterfaceDevice.current().play(.click)
    }

    func stopRecordingTap() {
        guard isCalibrating, isRecordingTap else { return }
        let samples = processor.stopRecordingTap()
        isRecordingTap = false
        WKInterfaceDevice.current().play(.success)
        analyzeRecordingBuffer(samples)
    }

    private func loadCalibrationSettings() {
        let defaults = UserDefaults.standard
        let savedDown = defaults.double(forKey: "STDownwardThreshold")
        let savedUp = defaults.double(forKey: "STUpwardThreshold")
        let savedTiming = defaults.double(forKey: "STDoubleTapTiming")

        if savedDown != 0 && savedUp != 0 && savedTiming != 0 {
            downwardThreshold = savedDown
            upwardThreshold = savedUp
            doubleTapTiming = savedTiming
            isCalibrated = true
        } else {
            downwardThreshold = -0.5
            upwardThreshold = 0.2
            doubleTapTiming = 0.4
            isCalibrated = false
        }

        processor.updateThresholds(down: downwardThreshold, up: upwardThreshold)
    }

    func saveCalibrationSettingsFromCompanion(down: Double, up: Double, timing: TimeInterval) {
        let defaults = UserDefaults.standard
        defaults.set(down, forKey: "STDownwardThreshold")
        defaults.set(up, forKey: "STUpwardThreshold")
        defaults.set(timing, forKey: "STDoubleTapTiming")
        loadCalibrationSettings()
    }

    private func saveCalibrationSettings(down: Double, up: Double, timing: TimeInterval) {
        let defaults = UserDefaults.standard
        defaults.set(down, forKey: "STDownwardThreshold")
        defaults.set(up, forKey: "STUpwardThreshold")
        defaults.set(timing, forKey: "STDoubleTapTiming")
        loadCalibrationSettings()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            Log.error(Log.motion, "[SurfaceTapDetector] DeviceMotion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        processor.resetDetection()
        tapCount = 0

        guard !motionManager.isDeviceMotionActive else { return }

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [processor, weak self] data, _ in
            guard let data = data else { return }
            let z = data.userAcceleration.z
            guard let event = processor.process(z: z, at: Date()) else { return }

            Task { @MainActor [weak self] in
                self?.handleMotionEvent(event)
            }
        }
    }

    private func handleMotionEvent(_ event: SurfaceTapMotionEvent) {
        guard isActive, !isCalibrating else { return }

        switch event {
        case .validatedTap(let timeSincePrevious):
            handleValidatedTap(timeSincePrevious: timeSincePrevious)
        }
    }

    private func handleValidatedTap(timeSincePrevious: TimeInterval) {
        WKInterfaceDevice.current().play(.click)

        tapCount += 1
        singleTapTask?.cancel()

        if tapCount == 2, abs(timeSincePrevious - doubleTapTiming) <= doubleTapTolerance {
            tapCount = 0
            singleTapTask = nil
            Log.info(Log.motion, "[SurfaceTapDetector] Double Tap Triggered!")
            onDoubleTap?()
        } else {
            tapCount = 1
            let waitForDoubleTapDuration = doubleTapTiming + doubleTapTolerance
            let waitNanoseconds = UInt64(max(0, waitForDoubleTapDuration) * 1_000_000_000)

            singleTapTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: waitNanoseconds)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self, self.isActive, !self.isCalibrating else { return }
                self.tapCount = 0
                self.singleTapTask = nil
                Log.info(Log.motion, "[SurfaceTapDetector] Single Tap Triggered!")
                self.onSingleTap?()
            }
        }
    }

    private func cancelPendingTap() {
        singleTapTask?.cancel()
        singleTapTask = nil
        tapCount = 0
    }

    private func analyzeRecordingBuffer(_ samples: [Double]) {
        guard !samples.isEmpty else { return }

        if calibrationPhase == .singleTaps {
            let minZ = samples.min() ?? 0
            let maxZ = samples.max() ?? 0

            if minZ < -0.1 && maxZ > 0.05 {
                collectedDownwardPeaks.append(minZ)
                collectedUpwardPeaks.append(maxZ)

                onCalibrationSampleComplete?(collectedDownwardPeaks.count, requiredSamplesPerPhase)
                Log.debug(Log.motion, "[Calibration] Valid single recorded. Down: \(minZ), Up: \(maxZ)")

                if collectedDownwardPeaks.count >= requiredSamplesPerPhase {
                    calibrationPhase = .doubleTaps
                    onPhaseChange?(.doubleTaps)
                    Log.info(Log.motion, "[Calibration] Advancing to Double Taps phase.")
                }
            } else {
                Log.debug(Log.motion, "[Calibration] Invalid single tap shape (too light). Min: \(minZ), Max: \(maxZ)")
            }
        } else if calibrationPhase == .doubleTaps {
            var lowestVal = 0.0
            var lowestIdx = -1

            for (i, val) in samples.enumerated() {
                if val < lowestVal {
                    lowestVal = val
                    lowestIdx = i
                }
            }

            if lowestIdx != -1 {
                var secondLowestVal = 0.0
                var secondLowestIdx = -1

                for (i, val) in samples.enumerated() {
                    if abs(i - lowestIdx) > 15 {
                        if val < secondLowestVal {
                            secondLowestVal = val
                            secondLowestIdx = i
                        }
                    }
                }

                if secondLowestIdx != -1 && secondLowestVal < -0.1 {
                    let timingS = Double(abs(lowestIdx - secondLowestIdx)) * 0.01
                    collectedDoubleTapTimings.append(timingS)

                    onCalibrationSampleComplete?(collectedDoubleTapTimings.count, requiredSamplesPerPhase)
                    Log.debug(Log.motion, "[Calibration] Valid double recorded. Timing: \(timingS)s")

                    if collectedDoubleTapTimings.count >= requiredSamplesPerPhase {
                        finalizeCalibration()
                    }
                } else {
                    Log.debug(Log.motion, "[Calibration] Invalid double tap (couldn't find two distinct strikes).")
                }
            }
        }
    }

    private func finalizeCalibration() {
        guard !collectedDownwardPeaks.isEmpty,
              !collectedUpwardPeaks.isEmpty,
              !collectedDoubleTapTimings.isEmpty else { return }

        let avgDown = collectedDownwardPeaks.reduce(0, +) / Double(collectedDownwardPeaks.count)
        let avgUp = collectedUpwardPeaks.reduce(0, +) / Double(collectedUpwardPeaks.count)
        let avgTiming = collectedDoubleTapTimings.reduce(0, +) / Double(collectedDoubleTapTimings.count)

        let finalDownThreshold = min(avgDown * 0.45, -0.1)
        let finalUpThreshold = max(avgUp * 0.45, 0.08)
        let finalTiming = max(0.15, min(avgTiming, 0.8))

        saveCalibrationSettings(down: finalDownThreshold, up: finalUpThreshold, timing: finalTiming)
        WatchConnectivityClient.shared.sendCalibration(down: finalDownThreshold, up: finalUpThreshold, timing: finalTiming)

        isCalibrating = false
        isRecordingTap = false
        calibrationPhase = .idle
        processor.setCalibrating(false)
        processor.cancelRecording()
        cancelPendingTap()
        motionManager.stopDeviceMotionUpdates()

        onCalibrationFinalComplete?()

        Log.info(Log.motion, "[SurfaceTapDetector] Calibration FINISHED! Set properties to = Down: \(finalDownThreshold), Up: \(finalUpThreshold), Timing: \(finalTiming)")
    }
}
