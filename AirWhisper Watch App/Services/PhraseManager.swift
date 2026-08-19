//Edited by   .
/*  
    manages quick speak on watch side - stores phrases, tracks usage, syncs with iPhone.
*/
import Foundation
import Combine

// Phrase model used on the Watch side.
struct WatchPhrase: Codable, Equatable {
    var text: String
    var useCount: Int
    
    init(text: String, useCount: Int = 0) {
        self.text = text
        self.useCount = useCount
    }
}

final class PhraseManager: ObservableObject {
    
    static let shared = PhraseManager() 
    
    static let maxPhrases = 10
    
    @Published private(set) var phrases: [WatchPhrase] = [] // array of phrases.
    //published - when value changes it notifies UI
    //private(set) - only this class can modify the phrases array, but other parts of the app can read it. prevent data from external modifications.
    
    var allPhrases: [String] {
        phrases.map { $0.text }
    }// return just the text for UI display.

    private let userDefaultsKey = "com.airwhisper.watchPhrases"
    //key used to store and retrieve the phrases from UserDefaults. To avoide conflict with other data in userdefaults.

    private let cloudStore = NSUbiquitousKeyValueStore.default
    private let cloudPhrasesKey = "phrases"
    // iCloud KVS as a secondary sync path  - phrases sync via cloud even when iPhone isn't nearby.
    
    private init() {
        loadPhrases()
        startObservingCloudChanges()
    }// private because we want only one instance, maintain singleton pattern.
    

    // load saved phrases from UserDefaults, falling back to iCloud if local is empty.
    private func loadPhrases() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([WatchPhrase].self, from: data) {
            phrases = saved
        } else if let cloudData = cloudStore.data(forKey: cloudPhrasesKey),
                  let cloudPhrases = try? JSONDecoder().decode([AWPhraseItem].self, from: cloudData) {
            // restore from iCloud if local is empty (new watch, same Apple ID)
            syncPhrasesFromiPhone(cloudPhrases)
        }
    }
    
    private func savePhrases() {
        if let data = try? JSONEncoder().encode(phrases) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        // also mirror to iCloud KVS as AWPhraseItem format (same format the iPhone uses)
        let items = phrases.map { AWPhraseItem(text: $0.text, useCount: $0.useCount) }
        if let cloudData = try? JSONEncoder().encode(items) {
            cloudStore.set(cloudData, forKey: cloudPhrasesKey)
        }
    }


    private func startObservingCloudChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
        cloudStore.synchronize()
    }
    // registers for iCloud KVS changes so phrases update even without WatchConnectivity.

    @objc private func cloudStoreDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
              (reason == NSUbiquitousKeyValueStoreServerChange ||
               reason == NSUbiquitousKeyValueStoreInitialSyncChange),
              let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
              changedKeys.contains(cloudPhrasesKey) else { return }

        // phrases changed on another device  - pull and apply
        guard let cloudData = cloudStore.data(forKey: cloudPhrasesKey),
              let items = try? JSONDecoder().decode([AWPhraseItem].self, from: cloudData) else { return }
        syncPhrasesFromiPhone(items)
    }
    // when iCloud delivers new phrase data from another device, apply it locally.
    
    // When a phrase is used, we want to promote it to the top of the list and update usage counts.
    
    func markPhraseUsed(_ phraseText: String) {
        let key = phraseText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let idx = phrases.firstIndex(where: { $0.text.uppercased() == key }) else { return }
        
        phrases[idx].useCount += 1
        
        savePhrases()
        objectWillChange.send()
        
        // Sync updated order back to iPhone
        syncPhrasesToiPhone()
    }
    
    // Phrase Management
    
    func addPhrase(_ phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return false }
        
        if phrases.contains(where: { $0.text.uppercased() == trimmed }) {
            return false
        }
        
        if phrases.count >= Self.maxPhrases {
            // Replace the phrase with the lowest useCount, excluding Help
            if let lfuIndex = phrases.enumerated()
                .filter({ $0.element.text.uppercased() != "HELP" })
                .min(by: { $0.element.useCount < $1.element.useCount })?.offset {
                phrases[lfuIndex] = WatchPhrase(text: trimmed, useCount: 0)
            }
        } else {
            phrases.append(WatchPhrase(text: trimmed))
        }
        
        savePhrases()
        syncPhrasesToiPhone()
        return true
    }
    
    // Remove a phrase at index (sorted order).
    func removePhrase(at index: Int) {
        guard index >= 0 && index < phrases.count else { return }
        let target = phrases[index]
        if target.text.uppercased() == "HELP" { return } // Protect Help
        phrases.remove(at: index)
        savePhrases()
        syncPhrasesToiPhone()
    }
    
    // Remove a phrase by value.
    func removePhrase(_ phrase: String) {
        let key = phrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if key == "HELP" { return } // Protect Help
        phrases.removeAll { $0.text.uppercased() == key }
        savePhrases()
        syncPhrasesToiPhone()
    }
    
    //Sync with iPhone - replace local phrases with the ones received from iPhone, ensuring no duplicates.
    func syncPhrasesFromiPhone(_ items: [AWPhraseItem]) {
        var seen: Set<String> = []
        var newPhrases: [WatchPhrase] = []
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
                newPhrases.append(WatchPhrase(text: normalized, useCount: item.useCount))
            }
        }
        
        // Help should always be present and at index 0
        let finalHelpCount = helpItem?.useCount ?? 0
        newPhrases.insert(WatchPhrase(text: "HELP", useCount: finalHelpCount), at: 0)
        
        // 10-phrase limit
        if newPhrases.count > Self.maxPhrases {
            newPhrases = Array(newPhrases.prefix(Self.maxPhrases))
        }
        
        phrases = newPhrases
        savePhrases()
    }

    func clearLocalPhrases() {
        phrases = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    
    //Sync back to iPhone - send the current list of phrases from watch to the iPhone, ensuring they are sorted by priority.
    
    private func syncPhrasesToiPhone() {
        let items = phrases.map { AWPhraseItem(text: $0.text, useCount: $0.useCount) }
        let payload = AWPhraseSyncPayload(type: .phraseSync, phraseItems: items)
        Task { @MainActor in
            WatchConnectivityClient.shared.sendPhraseSync(payload)
        }
    }
}
