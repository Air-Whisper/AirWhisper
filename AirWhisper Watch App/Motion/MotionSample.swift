// Every time the Apple Watch's IMU (Inertial Measurement Unit) sensor takes a reading,
// one MotionSample is created holding that snapshot of sensor data.
// Think of it as one "row" of sensor data captured at a single moment in time.

// 'import Foundation' gives us access to basic Swift types like Double, String, Array, etc.
// Foundation is Apple's core framework that almost every Swift file imports.
import Foundation

//  we are using 'struct' becuase it defines a VALUE TYPE in Swift (like an Int or String).
/* Unlike a 'class' (reference type), when you assign a struct to a new variable,
 it creates a COPY  - so two variables never accidentally share the same data.
This is perfect for sensor data: each sample is its own independent snapshot.
*/
struct MotionSample {

    // 'timestamp:Each timestamp marks the exact moment (in seconds since the Watch booted) when that one sensor reading was captured. It's not per-second though  it's per sample, which happens ~100 times per second.
    let timestamp: Double  

    // Gyroscope Data contians basic three vlaues =(roll ,pitch ,yaw) rotation rate around each axis, in radians per second

    // X-axis = roll (tilting left/right), Y-axis = pitch (tilting forward/back), Z-axis = yaw (twisting).
    let rotationRateX: Double
    let rotationRateY: Double
    let rotationRateZ: Double

    // Gravity Vector (direction of gravity in the device's coordinate frame)
    // This tells us which way "down" is relative to the watch's orientation.
    
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double

    // User Acceleration (acceleration applied by the user, with gravity removed)
    // CoreMotion automatically subtracts gravity, so these values represent ONLY the motion caused by the user's hand movement (in g-force units).


    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double

    // Quaternion components representing the device's attitude (orientation).
    // Used by the new preprocessor to rotate sensor data into world frame
    // during feature engineering (engineerFinalFeatures).
    let quaternionW: Double
    let quaternionX: Double
    let quaternionY: Double
    let quaternionZ: Double
    
    
    // Compatibility helper for legacy debug views that inspect the original 9 IMU channels.
    // The new ML pipeline uses quaternion-rotated world-frame features internally,
    // so this property is NOT used for inference  - it's kept for any debug/UI code
    // that still expects the old 9-channel format.

    var featureVector: [Double] {
        
        [
            rotationRateX, rotationRateY, rotationRateZ,
            gravityX, gravityY, gravityZ,
            accelerationX, accelerationY, accelerationZ,
        ]
    }
}