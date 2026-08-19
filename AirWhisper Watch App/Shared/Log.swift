import Foundation
import os
// Centralized logging utility using Apple's unified logging system.
enum Log {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "AirWhisper"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let motion = Logger(subsystem: subsystem, category: "motion")
    static let preprocess = Logger(subsystem: subsystem, category: "preprocess")
    static let ml = Logger(subsystem: subsystem, category: "coreml")
    static let wc = Logger(subsystem: subsystem, category: "watchconnectivity")

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)") 
    }

    static func debug(_ logger: Logger, _ message: String) {
        logger.debug("\(message, privacy: .public)") 
    }

    static func error(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
