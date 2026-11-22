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
    private let orderRevisionKey = "com.airwhisper.watch.phraseOrderRevision"
    private let activityRevisionKey = "com.airwhisper.watch.phraseActivityRevision"
    //key used to store and retrieve the phrases from UserDefaults. To avoide conflict with other data in userdefaults.

    private(set) var orderRevision = 0
    private(set) var activityRevision = 0

    /// The Watch no longer uses iCloud KVS for phrases. The iPhone owns the
    /// cloud backup (only for Apple ID sessions), and pushes phrases here over
    /// WatchConnectivity. This legacy Watch-only KVS key used to restore a
    /// stale snapshot on every fresh install, so purge it once.
    private let legacyCloudStore = NSUbiquitousKeyValueStore.default
    private let legacyCloudPhrasesKey = "phrases"

    private init() {
        orderRevision = UserDefaults.standard.integer(forKey: orderRevisionKey)
        activityRevision = UserDefaults.standard.integer(forKey: activityRevisionKey)
        loadPhrases()
        purgeLegacyCloudSnapshot()
    }// private because we want only one instance, maintain singleton pattern.

    private func purgeLegacyCloudSnapshot() {
        legacyCloudStore.removeObject(forKey: legacyCloudPhrasesKey)
        legacyCloudStore.synchronize()
    }

    /// Every local change advances the same wall-clock version the iPhone uses,
    /// so revisions from either device can be compared directly. Without this,
    /// a Watch-added phrase was sent with the iPhone's older orderRevision and
    /// got rejected by the companion as stale.
    private func bumpLocalRevision() {
        let now = Int(Date().timeIntervalSince1970 * 1_000)
        orderRevision = max(orderRevision + 1, now)
        activityRevision = 0
    }
    

    // Phrases are always pushed from the iPhone over WatchConnectivity. Only
    // the last synced list is cached locally - no iCloud restore on the Watch.
    private func loadPhrases() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let saved = try? JSONDecoder().decode([WatchPhrase].self, from: data) else { return }
        phrases = saved
    }

    private func savePhrases() {
        UserDefaults.standard.set(orderRevision, forKey: orderRevisionKey)
        UserDefaults.standard.set(activityRevision, forKey: activityRevisionKey)

        if let data = try? JSONEncoder().encode(phrases) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    // When a phrase is used, we want to promote it to the top of the list and update usage counts.
    
    func markPhraseUsed(_ phraseText: String) {
        let key = phraseText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let idx = phrases.firstIndex(where: { $0.text.uppercased() == key }) else { return }
        
        phrases[idx].useCount += 1

        let helpPhrase = phrases.first(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "HELP" })
        let rankedPhrases = phrases.enumerated()
            .filter { $0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "HELP" }
            .sorted { lhs, rhs in
                if lhs.element.useCount == rhs.element.useCount {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.useCount > rhs.element.useCount
            }
            .map { $0.element }
        phrases = rankedPhrases
        if let helpPhrase {
            phrases.insert(helpPhrase, at: 0)
        }
        bumpLocalRevision()

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
        
        bumpLocalRevision()
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
        bumpLocalRevision()
        savePhrases()
        syncPhrasesToiPhone()
    }
    
    // Remove a phrase by value.
    func removePhrase(_ phrase: String) {
        let key = phrase.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if key == "HELP" { return } // Protect Help
        phrases.removeAll { $0.text.uppercased() == key }
        bumpLocalRevision()
        savePhrases()
        syncPhrasesToiPhone()
    }
    
    //Sync with iPhone - replace local phrases with the ones received from iPhone, ensuring no duplicates.
    @discardableResult
    func syncPhrasesFromiPhone(
        _ items: [AWPhraseItem],
        orderRevision incomingOrderRevision: Int? = nil,
        activityRevision incomingActivityRevision: Int? = nil
    ) -> Bool {
        let incomingOrderRevision = incomingOrderRevision ?? 0
        let incomingActivityRevision = incomingActivityRevision ?? 0
        guard incomingOrderRevision > orderRevision ||
                (incomingOrderRevision == orderRevision && incomingActivityRevision >= activityRevision) else {
            return false
        }

        orderRevision = incomingOrderRevision
        activityRevision = incomingActivityRevision

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
        return true
    }

    func clearLocalPhrases() {
        phrases = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        orderRevision = 0
        activityRevision = 0
        UserDefaults.standard.removeObject(forKey: orderRevisionKey)
        UserDefaults.standard.removeObject(forKey: activityRevisionKey)
    }
    
    
    //Sync back to iPhone - send the current list of phrases from watch to the iPhone, ensuring they are sorted by priority.
    
    private func syncPhrasesToiPhone() {
        let items = phrases.map { AWPhraseItem(text: $0.text, useCount: $0.useCount) }
        let payload = AWPhraseSyncPayload(
            type: .phraseSync,
            phraseItems: items,
            orderRevision: orderRevision,
            activityRevision: activityRevision
        )
        Task { @MainActor in
            WatchConnectivityClient.shared.sendPhraseSync(payload)
        }
    }
}
