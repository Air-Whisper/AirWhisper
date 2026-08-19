import Foundation

struct User: Codable {
    var name: String
    var email: String?
    var appleUserIdentifier: String? // Store Apple ID for session verification
    
    init(name: String, email: String? = nil, appleUserIdentifier: String? = nil) {
        self.name = name
        self.email = email
        self.appleUserIdentifier = appleUserIdentifier
    }

    var displayContact: String {
        if let e = email, !e.isEmpty { return e }
        return "No contact info"
    }
}

// stores name/phone number of user, and is codable to allow for easy saving and loading from persistent storage.