import UIKit
struct MyPeople: Identifiable, Codable //Contact structure with avatar generation
{
    let id: UUID //Unique identifier for the contact
    var name: String //Contact name
    var phoneNumber: String? //Optional phone number
    init(id: UUID = UUID(), name: String, phoneNumber: String? = nil) 
    {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
    }
    var avatarLetter: String //returns the first letter of the contact's name for avatar display
    {
        return String(name.prefix(1)).uppercased()
    }
    var avatarColor: UIColor //returns a color for the contact's avatar based on the hash of the name
    {    let colors: [UIColor] = [
        UIColor(red: 200/255, green: 180/255, blue: 220/255, alpha: 1),
        UIColor(red: 220/255, green: 180/255, blue: 200/255, alpha: 1),
        UIColor(red: 180/255, green: 200/255, blue: 220/255, alpha: 1),
        UIColor(red: 200/255, green: 220/255, blue: 180/255, alpha: 1),
        UIColor(red: 220/255, green: 200/255, blue: 180/255, alpha: 1),
        UIColor(red: 180/255, green: 220/255, blue: 200/255, alpha: 1)
    ]
        let index = abs(name.hashValue) % colors.count
        return colors[index]
    }
}