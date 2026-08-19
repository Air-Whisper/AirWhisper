import Foundation
import WatchConnectivity
import Combine

@MainActor
final class WatchConnectivityClient: NSObject, ObservableObject {

    static let shared = WatchConnectivityClient()

    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isCompanionAppInstalled: Bool = true
    @Published private(set) var hasConfirmedCompanionSession: Bool
    @Published private(set) var companionReportsAuthenticated: Bool?
    @Published private(set) var hasReceivedInitialCompanionSync: Bool
    @Published private(set) var isReachable: Bool = false
    @Published private(set) var receivedPhrases: [String] = []
    @Published private(set) var receivedContacts: [AWContact] = []
    @Published private(set) var receivedSensitivity: Float?
    @Published private(set) var receivedVoiceGuidance: Bool = false
    @Published private(set) var receivedTapDetectorEnabled: Bool = false
    @Published private(set) var wasAccountDeleted: Bool
    @Published private(set) var currentAccessToken: String?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let initialCompanionSyncKey = "com.airwhisper.watch.initialCompanionSyncReceived"
    /// Records when voiceGuidance was last switched ON so we can ignore stale
    /// queued payloads that arrive shortly after and would set it back to false.
    private var voiceGuidanceEnabledAt: Date?

    private let confirmedCompanionSessionKey = "com.airwhisper.watch.confirmedCompanionSession"
    private let companionAuthKey = "com.airwhisper.watch.companionAuthenticated"
    private let accountDeletedKey = "com.airwhisper.watch.accountDeleted"

    private override init() {
        hasReceivedInitialCompanionSync = UserDefaults.standard.bool(forKey: initialCompanionSyncKey)
        hasConfirmedCompanionSession = UserDefaults.standard.bool(forKey: confirmedCompanionSessionKey)
        companionReportsAuthenticated = UserDefaults.standard.object(forKey: companionAuthKey) as? Bool
        wasAccountDeleted = UserDefaults.standard.bool(forKey: accountDeletedKey)
        super.init()

        currentAccessToken = UserDefaults.standard.string(forKey: "watchJWTToken")
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        refreshState(from: session)
        session.activate()
    }

    var companionSetupState: WatchCompanionSetupState {
        guard WCSession.isSupported() else { return .ready }

        guard activationState == .activated else {
            return .checking
        }

        guard isCompanionAppInstalled else {
            return .iphoneAppMissing
        }

        if companionReportsAuthenticated == false {
            return wasAccountDeleted ? .accountDeleted : .signInRequired
        }

        guard hasConfirmedCompanionSession else {
            return .waitingForInitialSync
        }

        guard hasReceivedInitialCompanionSync else {
            return .waitingForInitialSync
        }

        return .ready
    }

    func refreshCompanionSetupState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        refreshState(from: session)
        requestCompanionSetupStatusIfPossible(via: session)
    }

    func sendPhraseSync(_ payload: AWPhraseSyncPayload) {
        send(payload)
    }

    func sendCalibration(down: Double, up: Double, timing: TimeInterval) {
        let payload = AWCalibrationSyncPayload(
            type: .calibrationSync,
            downwardThreshold: down,
            upwardThreshold: up,
            doubleTapTiming: timing
        )
        send(payload)
    }

    func sendMessageToHistory(message: String, contactId: UUID? = nil, contactName: String? = nil) {
        let payload = AWMessagePayload(
            type: .messageHistory,
            message: message,
            timestamp: Date().timeIntervalSince1970,
            contactId: contactId,
            contactName: contactName
        )
        send(payload)
    }

    private func send<T: Encodable>(_ payload: T) {
        guard WCSession.isSupported() else { return }

        do {
            let data = try encoder.encode(payload)
            let session = WCSession.default
            isReachable = session.isReachable

            if session.isReachable {
                session.sendMessageData(data, replyHandler: nil) { [weak self] error in
                    Task { @MainActor in
                        self?.queueFallbackPayload(data)
                    }
                }
            } else {
                queueFallbackPayload(data)
            }
        } catch {
            Log.error(Log.wc, "WatchConnectivityClient: message encode/send failed  - \(error.localizedDescription)")
        }
    }

    private func queueFallbackPayload(_ data: Data) {
        WCSession.default.transferUserInfo(["payload": data])
    }

    private func handleIncomingPayloadData(_ data: Data) {
        guard let envelope = try? decoder.decode(AWPayloadEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case .contactSync:
            guard let contactPayload = try? decoder.decode(AWContactSyncPayload.self, from: data) else { return }
            markInitialCompanionSyncReceived()
            receivedContacts = contactPayload.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        case .phraseSync:
            guard let phrasePayload = try? decoder.decode(AWPhraseSyncPayload.self, from: data) else { return }
            markInitialCompanionSyncReceived()
            let items = phrasePayload.phraseItems
            receivedPhrases = items.map { $0.text }
            PhraseManager.shared.syncPhrasesFromiPhone(items)

        case .settingsSync:
            guard let settingsPayload = try? decoder.decode(AWSettingsSyncPayload.self, from: data) else { return }
            markInitialCompanionSyncReceived()
            receivedSensitivity = settingsPayload.sensitivity

            // Stale-payload guard: if voice guidance was enabled less than 1.5s ago,
            // ignore any incoming payload that tries to set it back to false.
            // This prevents out-of-order transferUserInfo packets (sent before the
            // user toggled ON) from immediately silencing the "Voice guidance enabled" utterance.
            let incomingVoiceGuidance = settingsPayload.voiceGuidance
            if !incomingVoiceGuidance, let enabledAt = voiceGuidanceEnabledAt,
               Date().timeIntervalSince(enabledAt) < 1.5 {
                // Stale downgrade  - keep the current enabled state, only update other fields
            } else {
                if incomingVoiceGuidance && !receivedVoiceGuidance {
                    voiceGuidanceEnabledAt = Date()
                } else if !incomingVoiceGuidance {
                    voiceGuidanceEnabledAt = nil
                }
                receivedVoiceGuidance = incomingVoiceGuidance
            }

            receivedTapDetectorEnabled = settingsPayload.tapDetectorEnabled

            if let down = settingsPayload.tapDownwardThreshold,
               let up = settingsPayload.tapUpwardThreshold,
               let timing = settingsPayload.tapDoubleTapTiming {
                SurfaceTapDetector.shared.saveCalibrationSettingsFromCompanion(down: down, up: up, timing: timing)
            }

        case .jwtToken:
            guard let jwt = try? decoder.decode(AWJWTPayload.self, from: data) else { return }
            markInitialCompanionSyncReceived()
            UserDefaults.standard.set(jwt.accessToken, forKey: "watchJWTToken")
            currentAccessToken = jwt.accessToken

        case .calibrationReset:
            SurfaceTapDetector.shared.resetCalibration()

        case .sessionReset:
            wasAccountDeleted = false
            UserDefaults.standard.removeObject(forKey: accountDeletedKey)
            resetCompanionSyncState()

        case .accountDeleted:
            wasAccountDeleted = true
            UserDefaults.standard.set(true, forKey: accountDeletedKey)
            resetCompanionSyncState()

        case .setupStatusResponse:
            guard let status = try? decoder.decode(AWSetupStatusResponsePayload.self, from: data) else { return }
            handleSetupStatusResponse(status)

        case .messageHistory, .setupStatusRequest, .calibrationSync:
            break
        }
    }

    private func refreshState(from session: WCSession) {
        activationState = session.activationState
        isReachable = session.isReachable
        isCompanionAppInstalled = session.isCompanionAppInstalled
    }

    private func markInitialCompanionSyncReceived() {
        hasConfirmedCompanionSession = true
        UserDefaults.standard.set(true, forKey: confirmedCompanionSessionKey)
        companionReportsAuthenticated = true
        UserDefaults.standard.set(true, forKey: companionAuthKey)
        wasAccountDeleted = false
        UserDefaults.standard.removeObject(forKey: accountDeletedKey)
        guard !hasReceivedInitialCompanionSync else { return }
        hasReceivedInitialCompanionSync = true
        UserDefaults.standard.set(true, forKey: initialCompanionSyncKey)
    }

    private func resetCompanionSyncState() {
        hasConfirmedCompanionSession = false
        UserDefaults.standard.removeObject(forKey: confirmedCompanionSessionKey)
        companionReportsAuthenticated = false
        UserDefaults.standard.set(false, forKey: companionAuthKey)
        hasReceivedInitialCompanionSync = false
        receivedPhrases = []
        receivedContacts = []
        receivedSensitivity = nil
        receivedVoiceGuidance = false
        receivedTapDetectorEnabled = false
        voiceGuidanceEnabledAt = nil
        currentAccessToken = nil

        UserDefaults.standard.removeObject(forKey: initialCompanionSyncKey)
        UserDefaults.standard.removeObject(forKey: "watchJWTToken")
        PhraseManager.shared.clearLocalPhrases()
        SurfaceTapDetector.shared.stop(for: "QuickSpeakView")
        SurfaceTapDetector.shared.resetCalibration()
    }

    private func handleSetupStatusResponse(_ status: AWSetupStatusResponsePayload) {
        companionReportsAuthenticated = status.isAuthenticated

        if status.isAuthenticated {
            hasConfirmedCompanionSession = true
            UserDefaults.standard.set(true, forKey: confirmedCompanionSessionKey)
            UserDefaults.standard.set(true, forKey: companionAuthKey)
        } else {
            resetCompanionSyncState()
        }
    }

    private func requestCompanionSetupStatusIfPossible(via session: WCSession) {
        guard !hasConfirmedCompanionSession else { return }

        guard session.activationState == .activated, session.isCompanionAppInstalled, session.isReachable else {
            return
        }

        let payload = AWSetupStatusRequestPayload(type: .setupStatusRequest)
        guard let data = try? encoder.encode(payload) else { return }

        session.sendMessageData(data) { [weak self] responseData in
            Task { @MainActor in
                guard let status = try? self?.decoder.decode(AWSetupStatusResponsePayload.self, from: responseData) else {
                    return
                }
                self?.handleSetupStatusResponse(status)
            }
        } errorHandler: { error in
            Log.error(Log.wc, "WatchConnectivityClient: setup status request failed  - \(error.localizedDescription)")
        }
    }

    func clearAccessToken() {
        currentAccessToken = nil
        UserDefaults.standard.removeObject(forKey: "watchJWTToken")
    }

    func requestTokenRefresh() {
        guard WCSession.isSupported() else { return }
        let payload = AWRefreshRequestPayload(type: .jwtRefreshRequest)
        guard let data = try? encoder.encode(payload) else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { error in
                Log.error(Log.wc, "WatchConnectivityClient: refresh request failed - \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(["payload": data])
        }
    }
}

extension WatchConnectivityClient: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshState(from: session)
            self.requestCompanionSetupStatusIfPossible(via: session)
            if let error {
                Log.error(Log.wc, "WatchConnectivityClient: session activation failed  - \(error.localizedDescription)")
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshState(from: session)
            self.requestCompanionSetupStatusIfPossible(via: session)
        }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshState(from: session)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.handleIncomingPayloadData(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Task { @MainActor in
            self.handleIncomingPayloadData(data)
        }
    }
}

enum WatchCompanionSetupState: Equatable {
    case checking
    case iphoneAppMissing
    case signInRequired
    case accountDeleted
    case waitingForInitialSync
    case ready
}

private struct AWPayloadEnvelope: Decodable {
    let type: AWPayloadType
}
