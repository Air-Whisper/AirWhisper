import Foundation
import CoreMotion
import Combine

final class OrientWriteMotionManager: ObservableObject {

    @Published private(set) var penPosition: CGPoint = CGPoint(x: 0.5, y: 0.5)

    @Published private(set) var isTracking: Bool = false

    @Published private(set) var isRecording: Bool = false

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    private let updateInterval: TimeInterval = 1.0 / 50.0
    private let smoothingFactor: Double = 0.2
    private let velocitySensitivity: Double = 0.012
    private let deadZone: Double = 0.05
    private let maxTiltAngle: Double = .pi / 6

    var sensitivityMultiplier: Double = 1.0

    private var filteredRollVelocity: Double = 0.0
    private var filteredPitchVelocity: Double = 0.0

    private var referenceRoll: Double = 0.0
    private var referencePitch: Double = 0.0

    private var currentX: Double = 0.5
    private var currentY: Double = 0.5

    private let stateLock = NSLock()

    private var defaultPositionX: CGFloat = 0.5
    private var defaultPositionY: CGFloat = 0.5

    init() {
        motionQueue.name = "com.airwhisper.orientwrite.motion"
        motionQueue.maxConcurrentOperationCount = 1
    }

    deinit {
        stopTracking()
    }

    func setStartPosition(isTopStart: Bool) {
        defaultPositionY = isTopStart ? 0.0 : 0.5
        defaultPositionX = 0.5
    }

    func resetPenPosition() {
        stateLock.lock()
        defer { stateLock.unlock() }
        currentX = Double(defaultPositionX)
        currentY = Double(defaultPositionY)
        filteredRollVelocity = 0.0
        filteredPitchVelocity = 0.0
        referenceRoll = 0.0
        referencePitch = 0.0

        let position = CGPoint(x: defaultPositionX, y: defaultPositionY)
        DispatchQueue.main.async { [weak self] in
            self?.penPosition = position
        }
    }

    func startPositioning() {
        guard motionManager.isDeviceMotionAvailable else {
            Log.error(Log.motion, "Device motion not available for OrientWrite")
            return
        }

        guard !isTracking else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval

        var isFirstUpdate = true

        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion else {
                if let error = error {
                    Log.error(Log.motion, "OrientWrite motion error: \(error.localizedDescription)")
                }
                return
            }

            let attitude = motion.attitude
            let roll = attitude.roll
            let pitch = attitude.pitch

            if isFirstUpdate {
                self.referenceRoll = roll
                self.referencePitch = pitch
                self.filteredRollVelocity = 0.0
                self.filteredPitchVelocity = 0.0
                isFirstUpdate = false
                return
            }

            var deltaRoll = roll - self.referenceRoll
            var deltaPitch = pitch - self.referencePitch

            if abs(deltaRoll) < self.deadZone {
                deltaRoll = 0.0
            } else {
                deltaRoll -= deltaRoll > 0 ? self.deadZone : -self.deadZone
            }

            if abs(deltaPitch) < self.deadZone {
                deltaPitch = 0.0
            } else {
                deltaPitch -= deltaPitch > 0 ? self.deadZone : -self.deadZone
            }

            let rollVelocity = max(-1.0, min(1.0, deltaRoll / self.maxTiltAngle))
            let pitchVelocity = max(-1.0, min(1.0, deltaPitch / self.maxTiltAngle))

            let smoothedRoll = self.filteredRollVelocity * (1.0 - self.smoothingFactor) + rollVelocity * self.smoothingFactor
            let smoothedPitch = self.filteredPitchVelocity * (1.0 - self.smoothingFactor) + pitchVelocity * self.smoothingFactor

            let effectiveSensitivity = self.velocitySensitivity * self.sensitivityMultiplier
            var newX = self.currentX + smoothedRoll * effectiveSensitivity
            var newY = self.currentY + smoothedPitch * effectiveSensitivity

            newX = max(0.0, min(1.0, newX))
            newY = max(0.0, min(1.0, newY))

            // Batch-write all shared mutable state under lock
            self.stateLock.lock()
            self.filteredRollVelocity = smoothedRoll
            self.filteredPitchVelocity = smoothedPitch
            self.currentX = newX
            self.currentY = newY
            self.stateLock.unlock()

            let newPosition = CGPoint(x: newX, y: newY)

            DispatchQueue.main.async { [weak self] in
                self?.penPosition = newPosition
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.isTracking = true
            self?.isRecording = false
        }

        Log.info(Log.motion, "OrientWrite positioning mode started")
    }

    func startRecording() {
        if !isTracking {
            startPositioning()
        }

        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
        }

        // Snapshot position under lock for logging (called from main thread)
        let (snapX, snapY): (Double, Double)
        stateLock.lock()
        snapX = currentX
        snapY = currentY
        stateLock.unlock()

        Log.info(
            Log.motion,
            "OrientWrite recording started from position (\(String(format: "%.2f", snapX)), \(String(format: "%.2f", snapY)))"
        )
    }

    func stopRecording() {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
        }

        Log.info(Log.motion, "OrientWrite recording stopped")
    }

    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
        stateLock.lock()
        defer { stateLock.unlock() }
        filteredRollVelocity = 0.0
        filteredPitchVelocity = 0.0

        DispatchQueue.main.async { [weak self] in
            self?.isTracking = false
            self?.isRecording = false
        }

        Log.info(Log.motion, "OrientWrite motion tracking stopped completely")
    }
}
