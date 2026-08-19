import Foundation

final class DataManager {
    static let shared = DataManager()
    private let storage = StorageManager.shared
    private let watch = WatchConnectivityManager.shared

    static let maxHistoryCount = 200 // cap message history to keep iCloud payload small (~15KB for 200 messages)

    private init() {}

    private(set) var currentUser: User? // the current user profile, if any. readable globally but writable locally.

    private var myPeople: [MyPeople] = []
    private var quickPhrases: [QuickPhrase] = []
    private var watchSettings: WatchSettings?
    private var messageHistory: [MessageHistory] = []
    // cache the personalisation meta for the user to constantly hitting UserDefaults.


    func startCloudSync() {
        storage.startObservingCloudChanges()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloudDataChange),
            name: .dataDidChangeRemotely,
            object: nil
        )
    }
    // called once at app launch to begin listening for iCloud changes from other devices.

    @objc private func handleCloudDataChange() {
        // reload all in-memory caches from storage (which now has the latest cloud values pulled in by StorageManager).
        _ = loadSavedData()
        watch.syncAllDataToWatch()
        // re-push to Watch so it gets the updated data from the other device.
    }
    // when iCloud data changes on another device, StorageManager pulls it into local UserDefaults and posts .dataDidChangeRemotely. We respond by refreshing our in-memory caches and re-syncing to Watch.

    /// Checks if iCloud has a saved user profile and restores it locally. Returns true if a cloud profile was restored.
    func restoreFromCloudIfNeeded() -> Bool {
        guard currentUser == nil, storage.hasCloudUser() else { return false }
        // only restore if there's no local user but iCloud has one (new device, same Apple ID).
        storage.restoreAllFromCloud()
        return loadSavedData()
    }
    // called during app launch to handle the case where a user installs on a new device but already has data in iCloud from their previous device.
    
    func setupNewUser(name: String, email: String? = nil, appleUserIdentifier: String? = nil) {
        let newUserId = appleUserIdentifier ?? email
        let previousUserId = storage.currentUserId

        let identityChanged: Bool
        if let prev = previousUserId, !prev.isEmpty, let newId = newUserId {
            identityChanged = prev != newId
        } else {
            identityChanged = false
        }

        if let newId = newUserId {
            storage.setCurrentUserId(newId)
        }

        let user = User(name: name, email: email, appleUserIdentifier: appleUserIdentifier) // create new user
        self.currentUser = user // store in memory

        storage.saveString(name, forKey: StorageManager.Keys.userName) // save username to UserDefaults + iCloud
        if let email = email {
            storage.saveString(email, forKey: StorageManager.Keys.userEmail) // save email to UserDefaults + iCloud
        }
        if let appleUserIdentifier = appleUserIdentifier {
            storage.saveString(appleUserIdentifier, forKey: StorageManager.Keys.appleUserIdentifier) // save apple identifier to UserDefaults + iCloud
        }

        // Pull the latest data from iCloud into local storage before checking
        storage.restoreAllFromCloud()

        if identityChanged {
            // Save the previous user's data before switching
            if let oldUserId = previousUserId, oldUserId != newUserId, !oldUserId.isEmpty {
                storage.backupData(for: oldUserId)
            }
        }

        let hasRestoredBackup = newUserId != nil ? storage.restoreBackup(for: newUserId!) : false

        if hasRestoredBackup {
            _ = loadSavedData()
        } else {
            // Try to load any existing data (e.g. from iCloud restore)
            let existingPhrases: [QuickPhrase]? = storage.load(forKey: StorageManager.Keys.phrases)

            if existingPhrases != nil {
                _ = loadSavedData()
            } else {
                self.myPeople = []
                self.quickPhrases = QuickPhrase.defaultPhrases()
                self.watchSettings = WatchSettings()
                self.messageHistory = []

                saveContacts()
                savePhrases()
                saveSettings()
                saveHistory()
            }
        }

        // sync everything to Watch immediately so it has the data when it starts up, rather than waiting for the user to trigger changes.
        watch.syncAllDataToWatch()
    }

    func loadSavedData() -> Bool {
        self.myPeople = storage.load(forKey: StorageManager.Keys.contacts) ?? []
        self.quickPhrases = storage.load(forKey: StorageManager.Keys.phrases) ?? QuickPhrase.defaultPhrases()
        let sensitivity = storage.loadFloat(forKey: StorageManager.Keys.settingsSensitivity) ?? WatchSettings.defaultValue
        let voiceGuidance = storage.loadBool(forKey: StorageManager.Keys.settingsVoiceGuidance)
        let tapDetectorEnabled = storage.loadBool(forKey: StorageManager.Keys.settingsTapDetectorEnabled)
        
        let tapDownwardThreshold = storage.load(forKey: StorageManager.Keys.settingsTapDownwardThreshold) as Double?
        let tapUpwardThreshold = storage.load(forKey: StorageManager.Keys.settingsTapUpwardThreshold) as Double?
        let tapDoubleTapTiming = storage.load(forKey: StorageManager.Keys.settingsTapDoubleTapTiming) as Double?

        self.watchSettings = WatchSettings(
            sensitivity: sensitivity,
            voiceGuidance: voiceGuidance,
            tapDetectorEnabled: tapDetectorEnabled,
            tapDownwardThreshold: tapDownwardThreshold,
            tapUpwardThreshold: tapUpwardThreshold,
            tapDoubleTapTiming: tapDoubleTapTiming
        )
        self.messageHistory = storage.load(forKey: StorageManager.Keys.messageHistory) ?? []

        guard let name = storage.loadString(forKey: StorageManager.Keys.userName) else {
            self.currentUser = nil
            return false
        }
        // check for user existence in UserDefaults, if missing then treat as no user and return false to show onboarding

        let email = storage.loadString(forKey: StorageManager.Keys.userEmail)
        let appleId = storage.loadString(forKey: StorageManager.Keys.appleUserIdentifier)

        self.currentUser = User(name: name, email: email, appleUserIdentifier: appleId)

        return true
        // if user data was successfully loaded, return true to proceed to main app. If any critical piece is missing (like username), return false to trigger onboarding.
    }


    enum WatchSignalReason {
        case signOut
        case accountDeleted
    }

    func clearCurrentUser(deleteCloudData: Bool = false, watchSignal: WatchSignalReason = .signOut) {
        if let userId = storage.currentUserId, !userId.isEmpty {
            if deleteCloudData {
                storage.deleteBackup(for: userId)
            } else {
                storage.backupData(for: userId)
            }
        }

        switch watchSignal {
        case .signOut:
            watch.sendSessionResetToWatch()
        case .accountDeleted:
            watch.sendAccountDeletedToWatch()
        }
        currentUser = nil
        myPeople = []
        quickPhrases = QuickPhrase.defaultPhrases()
        watchSettings = WatchSettings()
        messageHistory = []
        storage.clearAll(deleteCloudData: deleteCloudData)
        StorageManager.shared.setAppleIDSession(false)
        StorageManager.shared.setCurrentUserId("")
    }

    func clearUser(deleteCloudData: Bool = false, watchSignal: WatchSignalReason = .signOut) {
        clearCurrentUser(deleteCloudData: deleteCloudData, watchSignal: watchSignal)
        StorageManager.shared.clearSession()
        StorageManager.shared.setAppleIDSession(false)
    }

    static let maxContacts = 5 // maximum number of contacts allowed

    func getPeople() -> [MyPeople] {
        return myPeople
    }
    // returns the list of contacts, sorted by name. The UI can call this to get the current contacts to display.

    enum AddContactResult {
        case added
        case duplicate
        case limitReached
    }
    // result type for adding a contact, indicating success, duplicate detection, or limit reached

    @discardableResult // the caller can ignore the return value without a compiler warning.
    func add(_ person: MyPeople) -> AddContactResult {
        guard myPeople.count < Self.maxContacts else { return .limitReached }

        let isDuplicate = myPeople.contains { existing in
            let nameMatch = existing.name.compare(person.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            let phoneMatch: Bool
            switch (existing.phoneNumber, person.phoneNumber) {
            case let (a?, b?):
                phoneMatch = normalizePhone(a) == normalizePhone(b)
            case (nil, nil):
                phoneMatch = true
            default:
                phoneMatch = false
            }
            return nameMatch && phoneMatch
        }
        guard !isDuplicate else { return .duplicate }

        myPeople.append(person)
        saveContacts()
        return .added
    }
    // Adds a contact if it doesn't already exist (case-insensitive name and normalized phone). Enforces a maximum of 5 contacts. Returns an enum indicating the result.

    private func normalizePhone(_ phone: String) -> String {
        phone.filter { "+0123456789".contains($0) }
    }
    // Strips a phone string to digits and leading '+' for comparison.

    func remove(withId id: UUID) {
        myPeople.removeAll { $0.id == id }
        saveContacts()
    }
    // Removes a contact by its unique ID. This can be used if the UI is tracking contacts by ID rather than index.

    func search(query: String) -> [MyPeople] {
        guard !query.isEmpty else { return myPeople }
        return myPeople.filter { $0.name.lowercased().contains(query.lowercased()) }
    }
    // Searches contacts by name, case-insensitive. If the query is empty, returns all contacts.

    func find(byId id: UUID) -> MyPeople? {
        return myPeople.first { $0.id == id }
    }
    // Finds a contact by its unique ID, returning the contact if found or nil if not.

    func getQuickPhrases() -> [QuickPhrase] {
        return quickPhrases
    }
    // Returns the list of quick phrases. The UI can call this to display the phrases in the correct order.

    func getQuickPhraseTexts() -> [String] {
        return getQuickPhrases().map { $0.text }
    }
    // Returns the list of quick phrase texts. Used in managequickspeakviewcontroller for loading phrases in list.

    func getQuickPhraseItems() -> [AWPhraseItem] {
        return getQuickPhrases().map { AWPhraseItem(text: $0.text, useCount: $0.useCount) }
    }
    // Returns phrase items with useCount for syncing to Watch.

    static let maxPhrases = 10 // Maximum number of quick phrases allowed.

    
    @discardableResult
    func addQuickPhraseIfUnique(text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !containsPhrase(normalized) else { return false }
        if quickPhrases.count >= Self.maxPhrases {
            replaceLeastUsedPhrase(with: normalized)
        } else {
            let newPhrase = QuickPhrase(text: normalized)
            quickPhrases.append(newPhrase)
        }
        savePhrases()
        return true
    }
    // Adds a phrase only if no existing phrase matches (case-insensitive).
    // Enforces 10-phrase cap,replaces least-used if full.

    func replaceQuickPhrasesFromWatch(_ items: [AWPhraseItem]) {
        var seen: Set<String> = []
        var newPhrases: [QuickPhrase] = []
        var helpItem: AWPhraseItem?

        for item in items {
            let normalized = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.uppercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            if key == "HELP" {
                helpItem = item
            } else {
                newPhrases.append(QuickPhrase(text: normalized, useCount: item.useCount))
            }
        }

        // Help should always be present and at index 0
        let finalHelpCount = helpItem?.useCount ?? 0
        newPhrases.insert(QuickPhrase(text: "HELP", isDefault: true, useCount: finalHelpCount), at: 0)

        // Enforce limit
        if newPhrases.count > Self.maxPhrases {
            newPhrases = Array(newPhrases.prefix(Self.maxPhrases))
        }

        quickPhrases = newPhrases
        savePhrases(syncToWatch: false)
        NotificationCenter.default.post(name: .dataDidChangeRemotely, object: nil)
    }
    // replacing the phrase list with the one recieved from watch and saving it.

    func removeQuickPhrase(at index: Int) {
        guard index >= 0 && index < quickPhrases.count else { return }
        let target = quickPhrases[index]
        if target.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "HELP" { return } // Protect Help
        quickPhrases.remove(at: index)
        savePhrases()
    }
    // removing a phrase by index.

    
    private func replaceLeastUsedPhrase(with text: String) {
        // Exclude "Help" from being replaced
        guard let lfuIndex = quickPhrases.enumerated()
            .filter({ $0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "HELP" })
            .min(by: { $0.element.useCount < $1.element.useCount })?.offset else { return }
        
        quickPhrases[lfuIndex] = QuickPhrase(text: text, useCount: 0)
    }
    // Replace the least-used phrase with new text.

    private func containsPhrase(_ phrase: String) -> Bool {
        let key = phrase.uppercased()
        return quickPhrases.contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == key
        }
    }
    // Check if a phrase already exists, case-insensitive and ignoring whitespace.

    func getWatchSettings() -> WatchSettings? {
        return watchSettings
    }
    // Returns the current watch settings, or nil if not set. The UI can call this to load the current sensitivity value.

    func updateSensitivity(_ value: Float) {
        watchSettings?.sensitivity = value
        saveSettings()
    }
    // Updates the sensitivity value and saves the settings.


    func updateVoiceGuidance(_ value: Bool) {
        watchSettings?.voiceGuidance = value
        saveSettings()
    }
    // Updates the voice guidance boolean and saves the settings.

    func updateTapDetectorEnabled(_ value: Bool) {
        watchSettings?.tapDetectorEnabled = value
        saveSettings()
    }
    // Updates the tap detector boolean and saves the settings.
    
    func updateCalibration(down: Double, up: Double, timing: TimeInterval) {
        watchSettings?.tapDownwardThreshold = down
        watchSettings?.tapUpwardThreshold = up
        watchSettings?.tapDoubleTapTiming = timing
        saveSettings()
    }
    // Updates the calibration settings after the watch performs a new calibration.

    func resetSettingsToDefaults() {
        watchSettings = WatchSettings()
        quickPhrases = QuickPhrase.defaultPhrases()
        saveSettings()
        savePhrases()
        watch.sendCalibrationReset()
    }
    // Resets watch settings and quick phrases to factory defaults, then clears tap calibration on the Watch.

    func addMessage(_ message: MessageHistory) {
        messageHistory.append(message)
        saveHistory()
    }
    // Adds a new message to the history and saves it.

    func getGroupedHistory() -> [HistorySection] {
        let grouped = Dictionary(grouping: messageHistory) { $0.dateGroupLabel }

        return grouped.compactMap { key, messages -> HistorySection? in
            let items = messages.compactMap { msg -> HistoryItem? in
                guard let contact = find(byId: msg.contactId) else { return nil }
                return HistoryItem(messageHistory: msg, contact: contact)
            }
            guard !items.isEmpty, let firstDate = messages.first?.timestamp else { return nil }
            return HistorySection(title: key, date: firstDate, items: items.sorted { $0.messageHistory.timestamp > $1.messageHistory.timestamp })
        }.sorted { $0.date > $1.date }
    }
    // Groups message history into sections by date label (e.g. "Today", "Yesterday"), and sorts sections and messages within them by timestamp. Used for displaying in the history table view.

    private func saveContacts() {
        storage.save(myPeople, forKey: StorageManager.Keys.contacts)
        watch.sendContacts(myPeople)
    }
    // Saves the current contacts to UserDefaults and syncs them to the Watch.

    private func savePhrases(syncToWatch: Bool = true) {
        storage.save(quickPhrases, forKey: StorageManager.Keys.phrases)
        if syncToWatch {
            watch.sendPhrases(getQuickPhraseItems())
        }
    }
    // Saves the current quick phrases to UserDefaults and optionally syncs them to the Watch.

    private func saveSettings() {
        if let settings = watchSettings {
            storage.saveFloat(settings.sensitivity, forKey: StorageManager.Keys.settingsSensitivity)
            storage.saveBool(settings.voiceGuidance, forKey: StorageManager.Keys.settingsVoiceGuidance)
            storage.saveBool(settings.tapDetectorEnabled, forKey: StorageManager.Keys.settingsTapDetectorEnabled)
            if let down = settings.tapDownwardThreshold { storage.save(down, forKey: StorageManager.Keys.settingsTapDownwardThreshold) }
            if let up = settings.tapUpwardThreshold { storage.save(up, forKey: StorageManager.Keys.settingsTapUpwardThreshold) }
            if let timing = settings.tapDoubleTapTiming { storage.save(timing, forKey: StorageManager.Keys.settingsTapDoubleTapTiming) }
            
            watch.sendSettings(settings)
        }
    }
    // Saves the current watch settings to UserDefaults and syncs them to the Watch.

    private func saveHistory() {
        // keep only the most recent messages to stay well within iCloud KVS 1MB limit.
        if messageHistory.count > Self.maxHistoryCount {
            messageHistory = Array(messageHistory.suffix(Self.maxHistoryCount))
        }
        storage.save(messageHistory, forKey: StorageManager.Keys.messageHistory)
    }
    // Saves the current message history to UserDefaults + iCloud, capped at maxHistoryCount.
}


extension Notification.Name
{
    static let dataDidChangeRemotely = Notification.Name("dataDidChangeRemotely")
}
// Notification posted when data is changed from the Watch, so that relevant UI can refresh to reflect the changes. 
