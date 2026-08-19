//Edited by   .

//  struct to represent Quick Phrases because it represents plain data with no identity driven behaviour meaning value type usage (only being copied and updated) and does not need inheritance or reference sharing behavior.

import Foundation

struct QuickPhrase: Identifiable, Codable {
    let id: UUID
    var text: String
    var isDefault: Bool
    var useCount: Int

    init(id: UUID = UUID(), text: String, isDefault: Bool = false, useCount: Int = 0) {
        self.id = id
        self.text = text
        self.isDefault = isDefault
        self.useCount = useCount
    }
}
extension QuickPhrase {
    static let defaultTexts = ["Help", "Yes", "No", "I need water", "I'm in pain", "Food"]
    static func defaultPhrases() -> [QuickPhrase] {
        return defaultTexts.map { text in
            QuickPhrase(text: text, isDefault: true)
        }
    }
    static var defaultPhraseTexts: [String] {
        return defaultTexts
    }
}
