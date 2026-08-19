import UIKit
struct MessageHistory: Identifiable, Codable //Records a single sent or received message with timestamp and contact link
{
    let id: UUID // unique message id
    let contactId: MyPeople.ID //Links to the contact in MyPeople
    let message: String //Message text content
    let timestamp: Date //When the message was sent or received
    init(id: UUID = UUID(), contactId: UUID, message: String, timestamp: Date = Date()) 
    {
        self.id = id
        self.contactId = contactId
        self.message = message
        self.timestamp = timestamp
    }
    var formattedTime: String //Used in HistoryCell to display message time
    {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp) //Returns time in “3:45 PM” format
    }
    var dateGroupLabel: String //Used to create section headers in HistoryViewController
    {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) 
        {
            return "Today"
        } 
        else if calendar.isDateInYesterday(timestamp) 
        {
            return "Yesterday"
        } 
        else 
        {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMMM"
            return formatter.string(from: timestamp)
        }
    }
}
struct HistorySection 
{
    let title: String // Section header ("Today", "Yesterday", "14 March")
    let date: Date // First message's date used for sorting sections
    var items: [HistoryItem] // Messages in this section
}
struct HistoryItem 
{
    let messageHistory: MessageHistory // The actual message record
    let contact: MyPeople // The linked contact for easy access to name and avatar
    var name: String { contact.name }
    var message: String { messageHistory.message }
    var time: String { messageHistory.formattedTime }
    var avatarLetter: String { contact.avatarLetter }
    var avatarColor: UIColor { contact.avatarColor }
}