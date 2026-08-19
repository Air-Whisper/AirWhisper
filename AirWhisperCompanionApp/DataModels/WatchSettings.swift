import Foundation

struct WatchSettings: Codable {

    static let minValue: Float = 0
    static let maxValue: Float = 100
    static let defaultValue: Float = 50

    var sensitivity: Float = defaultValue {
        didSet {
            sensitivity = Self.clamp(sensitivity)
        }
    }
    // this propery has a didSet observer that ensures any assigned value is clamped within the defined minimum and maximum bounds, preventing invalid settings from being set.

    var voiceGuidance: Bool = false
    var tapDetectorEnabled: Bool = false
    var tapDownwardThreshold: Double?
    var tapUpwardThreshold: Double?
    var tapDoubleTapTiming: TimeInterval?


    private static func clamp(_ value: Float) -> Float {
        max(minValue, min(maxValue, value))
    }
    // a private helper method to clamp values within the defined range
}