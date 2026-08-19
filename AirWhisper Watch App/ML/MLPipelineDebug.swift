#if DEBUG
import Foundation

enum MLPipelineDebug {
    private static let debugDefaultsKey = "airwrite.ml.debug.enabled"

    static var isDebugEnabled: Bool {
        if ProcessInfo.processInfo.environment["AIRWRITE_ML_DEBUG"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: debugDefaultsKey)
    }
}
#endif
