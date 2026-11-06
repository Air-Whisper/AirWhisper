import Foundation

final class StorageManager {
    static let shared = StorageManager()

    private let localDefaults = UserDefaults.standard
    private let cloudDefaults = NSUbiquitousKeyValueStore.default
    private let keychain = KeychainStore.shared
    // dual storage: localDefaults for fast offline reads, cloudDefaults for iCloud sync across devices.

    private let kIsAppleIDSession = "aw_isAppleIDSession"
    private let kCurrentUserId = "aw_currentUserId"

    var isAppleIDSession: Bool {
        localDefaults.bool(forKey: kIsAppleIDSession)
    }

    func setAppleIDSession(_ value: Bool) {
        localDefaults.set(value, forKey: kIsAppleIDSession)
    }

    var currentUserId: String? {
        localDefaults.string(forKey: kCurrentUserId)
    }

    func setCurrentUserId(_ id: String) {
        localDefaults.set(id, forKey: kCurrentUserId)
    }

    private init() {
        migrateLegacySessionIfNeeded()
    }
    // stopping any creation of extra instances like let manager = StorageManager()

    struct Keys {
        static let userName = "userName"
        static let userEmail = "userEmail"
        static let appleUserIdentifier = "appleUserIdentifier"
        static let contacts = "contacts"
        static let phrases = "phrases"
        static let phraseOrderRevision = "phraseOrderRevision"
        static let phraseActivityRevision = "phraseActivityRevision"
        static let settingsSensitivity = "settings_sensitivity"
        static let settingsVoiceGuidance = "settings_voiceGuidance"
        static let settingsTapDetectorEnabled = "settings_tapDetectorEnabled"
        static let settingsTapDownwardThreshold = "settings_tapDownwardThreshold"
        static let settingsTapUpwardThreshold = "settings_tapUpwardThreshold"
        static let settingsTapDoubleTapTiming = "settings_tapDoubleTapTiming"
        static let messageHistory = "messageHistory"
        // Legacy UserDefaults keys retained only for migration cleanup.
        static let jwtAccessToken  = "jwtAccessToken"
        static let jwtRefreshToken = "jwtRefreshToken"
    }

    private struct JWTExpirationPayload: Decodable {
        let exp: TimeInterval?

        private enum CodingKeys: String, CodingKey {
            case exp
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let doubleValue = try? container.decode(Double.self, forKey: .exp) {
                exp = doubleValue
            } else if let intValue = try? container.decode(Int.self, forKey: .exp) {
                exp = TimeInterval(intValue)
            } else if let stringValue = try? container.decode(String.self, forKey: .exp),
                      let doubleValue = Double(stringValue) {
                exp = doubleValue
            } else {
                exp = nil
            }
        }
    }


    func startObservingCloudChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudDefaults
        )
        cloudDefaults.synchronize()
        removeLegacySessionDefaults()
    }
    // registers for iCloud KVS change notifications so we know when data changes on another device.

    @objc private func cloudStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // data changed on another device or initial sync completed  - pull cloud values into local defaults.
            if let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
                pullCloudToLocal(changedKeys: changedKeys)
            }
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            print("[Storage] iCloud KVS quota exceeded  - cloud writes will fail until data is reduced")
        default:
            break
        }
    }
    // handles incoming iCloud changes: pulls remote values into local UserDefaults, then notifies the app to refresh in-memory caches.

    private func pullCloudToLocal(changedKeys: [String]) {
        guard isAppleIDSession else { return }
        for key in changedKeys {
            guard key != Keys.jwtAccessToken, key != Keys.jwtRefreshToken else { continue }
            if let cloudValue = cloudDefaults.object(forKey: key) {
                localDefaults.set(cloudValue, forKey: key)
            }
        }
        // overwrite local UserDefaults with the latest cloud values for each changed key.

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .dataDidChangeRemotely, object: nil)
        }
        // notify the rest of the app that remote data arrived so DataManager and UI can refresh.
    }

    /// Checks if a user profile exists in iCloud (for new-device restore).
    func hasCloudUser() -> Bool {
        guard isAppleIDSession else { return false }
        return cloudDefaults.string(forKey: Keys.userName) != nil
    }
    // used at launch to detect if a returning user installed on a new device  - their profile is already in iCloud.

    /// Pulls all cloud data into local UserDefaults (one-time restore on new device).
    func restoreAllFromCloud() {
        guard isAppleIDSession else { return }
        let allKeys = [
            Keys.userName, Keys.userEmail, Keys.appleUserIdentifier,
            Keys.contacts, Keys.phrases, Keys.phraseOrderRevision, Keys.phraseActivityRevision,
            Keys.settingsSensitivity, Keys.settingsVoiceGuidance, Keys.settingsTapDetectorEnabled,
            Keys.settingsTapDownwardThreshold, Keys.settingsTapUpwardThreshold, Keys.settingsTapDoubleTapTiming,
            Keys.messageHistory
        ]
        for key in allKeys {
            if let cloudValue = cloudDefaults.object(forKey: key) {
                localDefaults.set(cloudValue, forKey: key)
            }
        }
    }
    // copies every known key from iCloud into local UserDefaults so that DataManager.loadSavedData() finds all data locally.


    func save<T: Encodable>(_ value: T, forKey key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            localDefaults.set(data, forKey: key)
            if isAppleIDSession { cloudDefaults.set(data, forKey: key) }
        } catch {
            print("[Storage] Failed to encode \(key): \(error)")
        }
    }
    // Generic save function that encodes any Codable type to both UserDefaults and iCloud KVS

    func save<T: Encodable, CloudValue: Encodable>(
        _ value: T,
        cloudValue: CloudValue,
        forKey key: String
    ) {
        do {
            let localData = try JSONEncoder().encode(value)
            localDefaults.set(localData, forKey: key)

            if isAppleIDSession {
                let cloudData = try JSONEncoder().encode(cloudValue)
                cloudDefaults.set(cloudData, forKey: key)
            }
        } catch {
            print("[Storage] Failed to encode \(key): \(error)")
        }
    }

    func saveLocal<T: Encodable>(_ value: T, forKey key: String) {
        do {
            localDefaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            print("[Storage] Failed to encode \(key): \(error)")
        }
    }

    func load<T: Decodable>(forKey key: String) -> T? {
        let source: Data?
        if isAppleIDSession {
            source = localDefaults.data(forKey: key) ?? cloudDefaults.data(forKey: key)
        } else {
            source = localDefaults.data(forKey: key)
        }
        if let data = source {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                print("[Storage] Failed to decode \(key): \(error)")
            }
        }
        return nil
    }
    // Generic load function that decodes any Codable type, checking local first then cloud.

    func saveString(_ value: String, forKey key: String) {
        if key == Keys.jwtAccessToken || key == Keys.jwtRefreshToken {
            keychain.save(value, for: key)
            removeLegacySessionDefaults()
            return
        }

        localDefaults.set(value, forKey: key)
        if isAppleIDSession { cloudDefaults.set(value, forKey: key) }
    }

    func loadString(forKey key: String) -> String? {
        if key == Keys.jwtAccessToken || key == Keys.jwtRefreshToken {
            return keychain.loadValue(for: key)
        }

        if isAppleIDSession {
            return localDefaults.string(forKey: key) ?? cloudDefaults.string(forKey: key)
        }
        return localDefaults.string(forKey: key)
    }

    func saveBool(_ value: Bool, forKey key: String) {
        localDefaults.set(value, forKey: key)
        if isAppleIDSession { cloudDefaults.set(value, forKey: key) }
    }

    func loadBool(forKey key: String) -> Bool {
        if localDefaults.object(forKey: key) != nil {
            return localDefaults.bool(forKey: key)
        }
        if isAppleIDSession {
            if cloudDefaults.object(forKey: key) != nil {
                return cloudDefaults.bool(forKey: key)
            }
        }
        return false
    }

    func saveFloat(_ value: Float, forKey key: String) {
        localDefaults.set(Double(value), forKey: key)
        if isAppleIDSession { cloudDefaults.set(Double(value), forKey: key) }
    }

    func loadFloat(forKey key: String) -> Float? {
        if localDefaults.object(forKey: key) != nil {
            return Float(localDefaults.double(forKey: key))
        }
        if isAppleIDSession {
            if cloudDefaults.object(forKey: key) != nil {
                return Float(cloudDefaults.double(forKey: key))
            }
        }
        return nil
    }
    // loading floats saved as doubles, checking local first then cloud fallback

     func hasExistingUser() -> Bool {
        return localDefaults.string(forKey: Keys.userName) != nil
    }
    // Checks if a user profile exists locally by looking for the presence of a username in UserDefaults

    func clearAll(deleteCloudData: Bool = false) {
        let allKeys = dataKeys
        for key in allKeys {
            localDefaults.removeObject(forKey: key)
            if deleteCloudData && isAppleIDSession {
                cloudDefaults.removeObject(forKey: key)
            }
        }
    }
    // Clears all stored data from both local UserDefaults and iCloud KVS

    private let dataKeys = [
        Keys.userName, Keys.userEmail, Keys.appleUserIdentifier,
        Keys.contacts, Keys.phrases, Keys.phraseOrderRevision, Keys.phraseActivityRevision,
        Keys.settingsSensitivity, Keys.settingsVoiceGuidance, Keys.settingsTapDetectorEnabled,
        Keys.settingsTapDownwardThreshold, Keys.settingsTapUpwardThreshold, Keys.settingsTapDoubleTapTiming,
        Keys.messageHistory
    ]

    /// Saves a snapshot of the current local data under backup keys so it can
    /// be restored if the same non-Apple user signs in again later.
    func backupData(for userId: String) {
        for key in dataKeys {
            if let value = localDefaults.object(forKey: key) {
                localDefaults.set(value, forKey: "backup_\(userId)_\(key)")
            }
        }
    }

    /// Deletes all backup keys for a given user, preventing indefinite accumulation
    /// and ensuring privacy on account deletion.
    func deleteBackup(for userId: String) {
        for key in dataKeys {
            localDefaults.removeObject(forKey: "backup_\(userId)_\(key)")
        }
    }

    /// Restores a previous user's backup to the standard keys. Returns true
    /// if any data was restored.
    func restoreBackup(for userId: String) -> Bool {
        var restored = false
        for key in dataKeys {
            let backupKey = "backup_\(userId)_\(key)"
            if let value = localDefaults.object(forKey: backupKey) {
                localDefaults.set(value, forKey: key)
                localDefaults.removeObject(forKey: backupKey)
                restored = true
            }
        }
        return restored
    }


    /// Persists access + refresh tokens in Keychain. Never written to UserDefaults
    /// or iCloud KVS because tokens are device-bound and should not roam.
    func saveSession(accessToken: String, refreshToken: String) {
        keychain.save(accessToken, for: Keys.jwtAccessToken)
        keychain.save(refreshToken, for: Keys.jwtRefreshToken)
        removeLegacySessionDefaults()
    }

    func loadAccessToken() -> String? {
        keychain.loadValue(for: Keys.jwtAccessToken)
    }

    func loadRefreshToken() -> String? {
        keychain.loadValue(for: Keys.jwtRefreshToken)
    }

    func hasValidSession() -> Bool {
        guard let token = loadRefreshToken() else { return false }
        if let expirationDate = jwtExpirationDate(for: token) {
            return expirationDate > Date()
        }
        return true
    }

    func clearSession() {
        keychain.deleteValue(for: Keys.jwtAccessToken)
        keychain.deleteValue(for: Keys.jwtRefreshToken)
        removeLegacySessionDefaults()
    }

    private func migrateLegacySessionIfNeeded() {
        let legacyAccessToken = localDefaults.string(forKey: Keys.jwtAccessToken)
        let legacyRefreshToken = localDefaults.string(forKey: Keys.jwtRefreshToken)

        if let accessToken = legacyAccessToken, let refreshToken = legacyRefreshToken {
            keychain.save(accessToken, for: Keys.jwtAccessToken)
            keychain.save(refreshToken, for: Keys.jwtRefreshToken)
        }

        removeLegacySessionDefaults()
    }

    private func removeLegacySessionDefaults() {
        localDefaults.removeObject(forKey: Keys.jwtAccessToken)
        localDefaults.removeObject(forKey: Keys.jwtRefreshToken)
        cloudDefaults.removeObject(forKey: Keys.jwtAccessToken)
        cloudDefaults.removeObject(forKey: Keys.jwtRefreshToken)
    }

    private func jwtExpirationDate(for token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(JWTExpirationPayload.self, from: data),
              let exp = payload.exp else { return nil }

        return Date(timeIntervalSince1970: exp)
    }
}
