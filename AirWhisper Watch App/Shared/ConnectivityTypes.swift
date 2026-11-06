import Foundation

// Connectivity types copy for watch side.
// AW = Air Whisper

enum AWPayloadType: String, Codable, Equatable {
    case phraseSync
    case messageHistory
    case contactSync
    case settingsSync
    case jwtToken
    case sessionReset
    case accountDeleted
    case setupStatusRequest
    case setupStatusResponse
    case calibrationReset
    case calibrationSync
}

struct AWJWTPayload: Codable {
    let type: AWPayloadType    // = .jwtToken
    let accessToken: String
}

struct AWSessionResetPayload: Codable {
    let type: AWPayloadType
}

struct AWSetupStatusRequestPayload: Codable {
    let type: AWPayloadType
}

struct AWSetupStatusResponsePayload: Codable {
    let type: AWPayloadType
    let isAuthenticated: Bool
}

struct AWContact: Codable, Identifiable { 
    let id: UUID
    let name: String
    let phoneNumber: String?
}

struct AWPhraseItem: Codable {
    let text: String
    let useCount: Int
    
    init(text: String, useCount: Int = 0) {
        self.text = text
        self.useCount = useCount
    }
}

struct AWPhraseSyncPayload: Codable {
    let type: AWPayloadType
    let phraseItems: [AWPhraseItem]
    let orderRevision: Int?
    let activityRevision: Int?

    init(
        type: AWPayloadType,
        phraseItems: [AWPhraseItem],
        orderRevision: Int? = nil,
        activityRevision: Int? = nil
    ) {
        self.type = type
        self.phraseItems = phraseItems
        self.orderRevision = orderRevision
        self.activityRevision = activityRevision
    }
}

struct AWContactSyncPayload: Codable {
    let type: AWPayloadType
    let contacts: [AWContact]
}

struct AWMessagePayload: Codable {
    let type: AWPayloadType
    let message: String
    let timestamp: TimeInterval
    let contactId: UUID?
    let contactName: String?
}

struct AWSettingsSyncPayload: Codable {
    let type: AWPayloadType
    let sensitivity: Float
    let voiceGuidance: Bool
    let tapDetectorEnabled: Bool
    let tapDownwardThreshold: Double?
    let tapUpwardThreshold: Double?
    let tapDoubleTapTiming: TimeInterval?
}

struct AWCalibrationResetPayload: Codable {
    let type: AWPayloadType   // = .calibrationReset
}

struct AWCalibrationSyncPayload: Codable {
    let type: AWPayloadType   // = .calibrationSync
    let downwardThreshold: Double
    let upwardThreshold: Double
    let doubleTapTiming: TimeInterval
}
