import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject  { // NSObject lets us use WCSessionDelegate which is an onjective c based protocol. This class is the central hub for all WatchConnectivity interactions on the iPhone side.

    static let shared = WatchConnectivityManager()

    private var session: WCSession?
    // optional because session can either exist or can not be supported on the device. We check for support before initializing.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var queuedContacts: [MyPeople]?
    private var queuedPhraseItems: [AWPhraseItem]?
    private var queuedSettings: WatchSettings?
    private var queuedJWTToken: String?
    private var queuedSessionReset = false
    /// Timestamp of the last full syncAllDataToWatch() call.
    /// Used to rate-limit reachability-triggered syncs so stale queued payloads
    /// do not overwrite freshly-toggled settings on the Watch.
    private var lastFullSyncAt: Date = .distantPast
    private let fullSyncDebounceInterval: TimeInterval = 2.0

    private override init() {
        super.init()
    }
    // Call this early in app lifecycle to set up the session and delegate.

    func activateSession() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] WCSession not supported on this device")
            return
        }
        session = WCSession.default // get session instance
        session?.delegate = self // set as delegate
        session?.activate() // activate communication session
    }

    func sendContacts(_ contacts: [MyPeople]) {
        guard let session = session else {
            queuedContacts = contacts
            print("[WatchConnectivity] Session unavailable, queued contacts")
            return
        }
        // to check if the session exists at all or not.

        guard session.activationState == .activated else {
            queuedContacts = contacts
            print("[WatchConnectivity] Session not activated, queued contacts")
            return
        }
        // to check if the session is activated.

        let payload = AWContactSyncPayload(
            type: .contactSync,
            contacts: contacts.map {
                AWContact(id: $0.id, name: $0.name, phoneNumber: $0.phoneNumber)
            }
        // formatting the iphone MyPeople into watch AWContact format for sending and errorfree receiving on the watch side.
        )

        do {
            let data = try encoder.encode(payload)
            sendDataPayload(data, via: session)
            queuedContacts = nil
            print("[WatchConnectivity] Sent \(contacts.count) contacts to Watch")
        } catch {
            print("[WatchConnectivity] Failed to encode contacts payload: \(error.localizedDescription)")
        }
        // encoding to binary to make contacts suitable for transmission.
    }

    func sendPhrases(_ items: [AWPhraseItem]) {
        guard let session = session else {
            queuedPhraseItems = items
            print("[WatchConnectivity] Session unavailable, queued phrase items")
            return
        }
        // to check if the session exists at all or not.

        guard session.activationState == .activated else {
            queuedPhraseItems = items
            print("[WatchConnectivity] Session not activated, queued phrase items")
            return
        }
        // to check if the session is activated.

        let uppercasedItems = items.map { AWPhraseItem(text: $0.text.uppercased(), useCount: $0.useCount) }
        let payload = AWPhraseSyncPayload(type: .phraseSync, phraseItems: uppercasedItems)
        // creating a payload with the uppercased phrase items, as the watch app expects them in uppercase for consistency and display purposes.
        do {
            let data = try encoder.encode(payload)
            sendDataPayload(data, via: session)
            queuedPhraseItems = nil
            print("[WatchConnectivity] Sent \(items.count) phrase items to Watch")
        } catch {
            print("[WatchConnectivity] Failed to encode phrase items payload: \(error.localizedDescription)")
        }
    }

    func sendSettings(_ settings: WatchSettings) {
        guard let session = session else {
            queuedSettings = settings
            return
        }
        // to check if the session exists at all or not.

        guard session.activationState == .activated else {
            queuedSettings = settings
            return
        }
        // to check if the session is activated.

        let payload = AWSettingsSyncPayload(
            type: .settingsSync,
            sensitivity: settings.sensitivity,
            voiceGuidance: settings.voiceGuidance,
            tapDetectorEnabled: settings.tapDetectorEnabled,
            tapDownwardThreshold: settings.tapDownwardThreshold,
            tapUpwardThreshold: settings.tapUpwardThreshold,
            tapDoubleTapTiming: settings.tapDoubleTapTiming
        )
        // creating a payload to send the watch settings.

        do {
            let data = try encoder.encode(payload)
            sendDataPayload(data, via: session)
            queuedSettings = nil
            print("[WatchConnectivity] Sent settings to Watch")
        } catch {
            print("[WatchConnectivity] Failed to encode settings payload: \(error.localizedDescription)")
        }
        // encoding to binary to make settings suitable for transmission.
    }

    private func flushPendingPayloads(via session: WCSession) {
        guard session.activationState == .activated else { return } // check if session is activated.

        if let contacts = queuedContacts {
            sendContacts(contacts)
        } // if there are any queued contacts, send them now that the session is active.

        if let phraseItems = queuedPhraseItems {
            sendPhrases(phraseItems)
        } // if there are any queued phrase items, send them now that the session is active.

        if let settings = queuedSettings {
            sendSettings(settings)
        } // if there are any queued settings, send them now that the session is active.

        if let token = queuedJWTToken {
            queuedJWTToken = nil
            sendJWTToken(token)
        }

        if queuedSessionReset {
            queuedSessionReset = false
            sendSessionResetToWatch()
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WatchConnectivity] Activation failed: \(error.localizedDescription)")
            return
        }
        print("[WatchConnectivity] Session activated: \(activationState.rawValue)")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("WatchConnectionStatusChanged"), object: nil)
            self.flushPendingPayloads(via: session)
            self.syncAllDataToWatch()
            self.sendStoredJWTTokenIfAvailable()
        }
    } // called when the session activation completes, either successfully or with an error. If successful, it flushes any queued payloads and syncs all data to the Watch.

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivity] Reachability changed: \(session.isReachable)")
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("WatchConnectionStatusChanged"), object: nil)
        }
        
        guard session.isReachable else { return }

        DispatchQueue.main.async {
            self.flushPendingPayloads(via: session)
            // Rate-limit full syncs: if we already did a full sync within the
            // debounce window, skip  - avoids sending stale settings payloads that
            // would overwrite a freshly-toggled value (e.g. voiceGuidance) on Watch.
            let now = Date()
            guard now.timeIntervalSince(self.lastFullSyncAt) >= self.fullSyncDebounceInterval else {
                print("[WatchConnectivity] Skipping redundant reachability sync (debounced)")
                return
            }
            self.syncAllDataToWatch()
        }
    } // called when the reachability of the session changes, meaning the ability to communicate with the Watch has changed. If the Watch becomes reachable, it flushes any queued payloads and syncs all data to the Watch.

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchConnectivity] Session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivity] Session deactivated, reactivating...")
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        handleIncomingPayloadData(messageData, reply: nil)
    } // called when a message is received from the Watch without a reply handler. It processes the incoming data payload.

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        handleIncomingPayloadData(messageData, reply: replyHandler)
    } // called when a message is received from the Watch with a reply handler. It processes the incoming data payload and can send a reply if needed.

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payloadData = userInfo["payload"] as? Data else { return }
        handleIncomingPayloadData(payloadData, reply: nil)
    }

    private func sendDataPayload(_ data: Data, via session: WCSession) {
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { error in
                print("[WatchConnectivity] sendMessageData error: \(error.localizedDescription)")
                session.transferUserInfo(["payload": data])
            }
        } else {
            session.transferUserInfo(["payload": data])
        }
    } // send data payloads to the Watch.

    private func handleIncomingPayloadData(_ data: Data, reply: ((Data) -> Void)?) {
        guard let envelope = try? decoder.decode(AWPayloadEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case .setupStatusRequest:
            sendSetupStatusReply(reply)

        case .phraseSync:
            guard let phrasePayload = try? decoder.decode(AWPhraseSyncPayload.self, from: data) else { return }
            DispatchQueue.main.async {
                let items = phrasePayload.phraseItems
                DataManager.shared.replaceQuickPhrasesFromWatch(items)
            }

        case .messageHistory:
            guard let messagePayload = try? decoder.decode(AWMessagePayload.self, from: data) else { return }
            recordHistoryFromWatch(messagePayload)

        case .calibrationSync:
            guard let calPayload = try? decoder.decode(AWCalibrationSyncPayload.self, from: data) else { return }
            DispatchQueue.main.async {
                DataManager.shared.updateCalibration(
                    down: calPayload.downwardThreshold,
                    up: calPayload.upwardThreshold,
                    timing: calPayload.doubleTapTiming
                )
            }
        
        case .jwtRefreshRequest:
            print("[WatchConnectivity] Watch requested a token refresh!")
            Task {
                do {
                    // This calls the backend, gets a new token, saves it to Keychain,
                    // and automatically calls sendJWTToken() to push it back to the watch.
                    _ = try await AuthService.refreshAccessToken()
                } catch {
                    print("[WatchConnectivity] Failed to refresh token for watch: \(error)")
                }
            }

        default:
            break
        } // if the message payload is a message history type, record it in the data manager.
    }

    private func sendSetupStatusReply(_ reply: ((Data) -> Void)?) {
        guard let reply else { return }

        let payload = AWSetupStatusResponsePayload(
            type: .setupStatusResponse,
            isAuthenticated: DataManager.shared.currentUser != nil && StorageManager.shared.hasValidSession()
        )

        guard let data = try? encoder.encode(payload) else { return }
        reply(data)
    }

    private func recordHistoryFromWatch(_ payload: AWMessagePayload) {
        DispatchQueue.main.async {
            guard let contact = self.resolveContact(for: payload) else {
                return
            } // resolve the contact associated with the incoming message payload. If it can't be resolved, dont record the history.

            let timestampDate = Date(timeIntervalSince1970: payload.timestamp)
            let history = MessageHistory(contactId: contact.id, message: payload.message, timestamp: timestampDate)
            DataManager.shared.addMessage(history)
        } // create a MessageHistory object from the payload and add it to the data manager, which will persist it and make it available in the app's history view.
    }

    private func resolveContact(for payload: AWMessagePayload) -> MyPeople? {
        if let contactId = payload.contactId,
           let matchById = DataManager.shared.find(byId: contactId) {
            return matchById
        } // first try to resolve the contact by its UUID.

        guard let contactName = payload.contactName?.trimmingCharacters(in: .whitespacesAndNewlines), !contactName.isEmpty else {
            return nil
        } // if UUID resolution fails, try to resolve by name, ignoring case and diacritics for a more forgiving match.

        return DataManager.shared.getPeople().first {
            $0.name.compare(contactName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } // if a contact is found that matches the name, return it. Otherwise, return nil.
    }

    func sendJWTToken(_ token: String) {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[WatchConnectivity] Skipping empty JWT token")
            return
        }
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] WCSession not supported, cannot send JWT token")
            return
        }

        let payload = AWJWTPayload(type: .jwtToken, accessToken: token)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let sess = session ?? WCSession.default
        guard sess.activationState == .activated else {
            queuedJWTToken = token
            print("[WatchConnectivity] Session not activated, queued JWT token")
            return
        }
        queuedSessionReset = false
        sendDataPayload(data, via: sess)
        print("[WatchConnectivity] Sent JWT token to Watch")
    }

    func sendSessionResetToWatch() {
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] WCSession not supported, cannot send session reset")
            return
        }

        let payload = AWSessionResetPayload(type: .sessionReset)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let sess = session ?? WCSession.default
        guard sess.activationState == .activated else {
            queuedSessionReset = true
            print("[WatchConnectivity] Session not activated, queued session reset")
            return
        }

        sendDataPayload(data, via: sess)
        print("[WatchConnectivity] Sent session reset to Watch")
    }

    func sendAccountDeletedToWatch() {
        guard WCSession.isSupported() else { return }

        let payload = AWSessionResetPayload(type: .accountDeleted)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let sess = session ?? WCSession.default
        guard sess.activationState == .activated else {
            queuedSessionReset = true
            return
        }

        sendDataPayload(data, via: sess)
    }

    func sendCalibrationReset() {
        guard WCSession.isSupported() else { return }

        let payload = AWCalibrationResetPayload(type: .calibrationReset)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let sess = session ?? WCSession.default
        guard sess.activationState == .activated else { return }

        sendDataPayload(data, via: sess)
    }

    func sendStoredJWTTokenIfAvailable() {
        guard StorageManager.shared.hasValidSession(),
              let token = StorageManager.shared.loadAccessToken() else {
            print("[WatchConnectivity] No valid JWT token available to send")
            return
        }
        sendJWTToken(token)
    }

    func syncAllDataToWatch() {
        guard DataManager.shared.currentUser != nil, StorageManager.shared.hasValidSession() else {
            return
        }

        queuedSessionReset = false
        lastFullSyncAt = Date()
        let contacts = DataManager.shared.getPeople()
        let phraseItems = DataManager.shared.getQuickPhraseItems()
        let settings = DataManager.shared.getWatchSettings()

        sendContacts(contacts)
        sendPhrases(phraseItems)
        if let s = settings {
            sendSettings(s)
        }
    } // sync all relevant data (contacts, phrases, settings) to the Watch.
}

private struct AWPayloadEnvelope: Decodable {
    let type: AWPayloadType
}

