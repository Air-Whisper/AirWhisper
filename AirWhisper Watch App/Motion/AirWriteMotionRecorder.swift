import CoreMotion
import Combine
import Foundation


//we use final here to prevent other classes from inheriting this class and it also help swift compiler to optimise code
// ': ObservableObject'  - a protocol that tells SwiftUI "I have @Published properties that

final class AirWriteMotionRecorder: ObservableObject {
    
    @Published private(set) var isRecording: Bool = false
    
    
    private let manager = CMMotionManager()
    
    private let maxSamples = 12000

    // : OperationQueue  - The type. OperationQueue is Apple's built-in class for managing tasks.
    
    private let queue: OperationQueue = { 
        let q = OperationQueue()
        q.name = "AirWriteMotionRecorder.queue"
        q.maxConcurrentOperationCount = 1 // it states only one task runs one at a time and this makes  it a serial queue instead of concurrent queue  two motion sensor readings arrive at the exact same moment. Both try to add data to the same array simultaneously. This is called a race condition - and it can crashes app or corrupt data.
        q.qualityOfService = .userInitiated // it states that that task is of highest priority.
        return q
    }()
    
    private let lock = NSLock()  //NSLock is a mutex 

    // Motion callbacks run on 'queue' (background), but we also read the buffer from the main thread. Without the lock, reading and writing could overlap 
    
    private var samplesBuffer: [MotionSample] = []
    private var loggedSampleMilestone: Int = 0
    

    //Internal flag to track recording state.
    private var isRecordingInternally: Bool = false
    
  
    

    //it is a closure that takes array of motionsamples and return void and passes entire array of motion sample to the caller .
    //
    var onLetterComplete: ((Int, [MotionSample]) -> Void)?

    private var samplingRateHz: Double = 100.0
    private var recordingSessionID: Int = 0


    // Basic destructor that is caled automatically when the object is deallocatded fromthe memory .
    //preventing sesnor from draining battery 
    deinit {
        manager.stopDeviceMotionUpdates()
    }
    

    // this block was made for future purpsoe to read the smaple buferfor UI.
    // var samples: [MotionSample] {
    //     lock.lock() 
    //     defer { lock.unlock() } 
    //     return samplesBuffer
    // }

    var currentSessionID: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordingSessionID
    }


    func startRecording() {
        lock.lock()  // locks saple buffer so the oter thread cant read sample buffer 
        defer { lock.unlock() } // unlcoks so that other thread can read sample buffer 
        


        // preventive measure to avoid starting multiple recording sesiions at the same time .
        guard !isRecordingInternally else {
            Log.debug(Log.motion, "startRecording() called while already recording")
            return
        }
        

        // check for the senosrs like it will not work on simulator and some old devices .
        guard manager.isDeviceMotionAvailable else {
            Log.error(Log.motion, "Device motion unavailable")
            return
        }
        
        
        samplesBuffer.removeAll(keepingCapacity: true) // clears buffer for a fresh recording.
        loggedSampleMilestone = 0 // resets milestone for logging progress.
        recordingSessionID += 1
        isRecordingInternally = true // sets internal flag to indicate recording has started.
        
        
        manager.deviceMotionUpdateInterval = 1.0 / samplingRateHz //update interval of motion sample .

        Log.info(Log.motion, String(format: "Starting motion recording @%.1fHz", samplingRateHz)) //
        

        // Update the @Published 'isRecording' on the MAIN thread.
        DispatchQueue.main.async {
            self.isRecording = true
        }
        

        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            guard let self, let m = motion else {
                if let error {
                    Log.error(Log.motion, "Motion error: \(error.localizedDescription)")
                }
                return
            }
             //This processes single motion reading (runs on the background queue).
            self.processMotionSample(m)
        }
    }
    

    // This method stops the motion recording, captures the final set of samples, and calls the completion handler with the captured data.
    func stopRecording() {
        manager.stopDeviceMotionUpdates() //stops sensor hardware from delivering updates.
        
        lock.lock()
        let wasRecording = isRecordingInternally
        let completedSessionID = recordingSessionID
        isRecordingInternally = false

        let capturedSamples = samplesBuffer //copy buffer to local variable before clearing it.
        samplesBuffer.removeAll(keepingCapacity: true)
        lock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            
        }
        
        // if we were in the middle of writing a letter (or in non-threshold mode), process the remaining buffer
        if wasRecording && !capturedSamples.isEmpty {
            Log.info(Log.motion, "Recording stopped with \(capturedSamples.count) samples captured")
            onLetterComplete?(completedSessionID, capturedSamples)
        }
        
        Log.info(Log.motion, "Stopped motion recording")
    }

    //runs on background operation queue and runs for each motion sample every second 100 times.
    private func processMotionSample(_ motion: CMDeviceMotion) {
        
        
        lock.lock()
        guard isRecordingInternally else {
            lock.unlock()
            return
        }

        
        // The new model's preprocessor (engineerFinalFeatures) handles
        // orientation correction internally using raw quaternion data to
        // rotate into world frame  - no calibration matrix is applied here.
        let q = motion.attitude.quaternion

        let sample = MotionSample(
            timestamp: motion.timestamp,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            gravityX: motion.gravity.x,
            gravityY: motion.gravity.y,
            gravityZ: motion.gravity.z,
            accelerationX: motion.userAcceleration.x,
            accelerationY: motion.userAcceleration.y,
            accelerationZ: motion.userAcceleration.z,
            quaternionW: q.w,
            quaternionX: q.x,
            quaternionY: q.y,
            quaternionZ: q.z
        )
        
        samplesBuffer.append(sample)
        
        if samplesBuffer.count > maxSamples {
            samplesBuffer.removeFirst(samplesBuffer.count - maxSamples)
        }
        
        //logging functions.
        let c = samplesBuffer.count
        if c >= loggedSampleMilestone + 500 {
            loggedSampleMilestone = (c / 500) * 500
            Log.debug(Log.motion, "Recording samples=\(c)")
        }
        lock.unlock()
    }
}
