import UIKit
import ContactsUI

class ContactsViewController: UIViewController //Displays list of saved contacts, allows import from device contacts, search, and delete.
{
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var contactsTableView: UITableView!
    @IBOutlet weak var emptyStateContainerView: UIView!
    @IBOutlet weak var emptyStateImageView: UIImageView!
    @IBOutlet weak var emptyStateLabel: UILabel!
    private var allContacts: [MyPeople] = [] // List of contacts loaded from DataManager
    private var searchResults: [MyPeople] = []
    private var isSearching = false
    
    override func viewDidLoad() //Sets up the view, loads contacts, and sets the title of the view to "My People".
    {
        super.viewDidLoad()
        title = "My People"
        setupVerifiedContacts()
        loadContacts()
    }

    private func setupVerifiedContacts() {
        let currentContacts = DataManager.shared.getPeople()
        let verifiedNames = ["John Doe"]
        
        let hasAllVerified = verifiedNames.allSatisfy { name in
            currentContacts.contains { $0.name == name }
        }
        
        if !hasAllVerified || currentContacts.count != 1 {
            for contact in currentContacts {
                DataManager.shared.remove(withId: contact.id)
            }
            
            let verifiedNumbers = [
                MyPeople(name: "John Doe", phoneNumber: "0000000000")
            ]
            for person in verifiedNumbers {
                DataManager.shared.add(person)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) // Reloads contacts every time the view appears to reflect any changes made (like adding/removing contacts).
    {
        super.viewWillAppear(animated)
        loadContacts()
    }

    private func loadContacts() // Fetches contacts from DataManager, updates the table view, and manages the empty state visibility.
    {
        allContacts = DataManager.shared.getPeople()
        searchResults = allContacts
        contactsTableView.reloadData()
        
        let isEmpty = allContacts.isEmpty
        emptyStateContainerView?.isHidden = !isEmpty
        contactsTableView?.isHidden = isEmpty
        searchBar?.isHidden = isEmpty
        
    }

    @IBAction func importFromDeviceTapped(_ sender: UIButton) //Called when the user taps the "Import from Device" button.
    {
        showAlert(title: "Paid Feature", message: "This is a paid feature and will be added soon")
    }

    private func showAlert(title: String, message: String) 
    {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributedMessage = NSMutableAttributedString(
            string: message,
            attributes: [
                NSAttributedString.Key.paragraphStyle: paragraphStyle,
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13)
            ]
        )
        alert.setValue(attributedMessage, forKey: "attributedMessage")
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if alert.isViewLoaded && alert.view.window != nil {
                alert.dismiss(animated: true, completion: nil)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTourIfNeeded()
    }

    // shows a guided tour on first app install to explain the contacts screen.
    private func showTourIfNeeded() {
        var steps: [CoachStep] = []
        if allContacts.isEmpty {
            steps.append(CoachStep(targetView: emptyStateContainerView, message: "No contacts yet  - tap 'Import from Device' to get started.", position: .above))
        } else {
            steps.append(CoachStep(targetView: searchBar, message: "Type a name to quickly find a contact.", position: .below))
            steps.append(CoachStep(targetView: contactsTableView, message: "Your contacts appear here. Swipe left on any contact to delete it.", position: .above))
        }
        CoachMarkManager.shared.showTourIfNeeded(on: self, steps: steps,  screenKey: "contacts")
    }
}

extension ContactsViewController: UITableViewDelegate, UITableViewDataSource 
{
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int //Tells the table view how many rows to display, if isSearching is true, it returns the count of searchResults, otherwise it returns the count of allContacts.
    {
        return isSearching ? searchResults.count : allContacts.count
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell //Configures each cell in the table view.
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ContactCell", for: indexPath) as! PersonCell //Asks the table view to provide a reusable cell with the identifier "ContactCell" and casts it to the custom PersonCell type.
        let contact = isSearching ? searchResults[indexPath.row] : allContacts[indexPath.row]
        cell.configure(with: contact)
        return cell
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat //Specifies the height(50) for each row in the table view.
    {
        return 50
    }
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool //Determines whether a particular row can be edited (in this case, all rows can be edited to allow deletion).
    {
        return false // Disable deletion for beta version verified contacts
    }
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) //Handles the deletion of contacts when the user swipes to delete a row.
    {
        if editingStyle == .delete //User swiped and tapped the delete button.
        {
            let contact = isSearching ? searchResults[indexPath.row] : allContacts[indexPath.row] //Get the contact to delete based on whether we're in search mode or not.
            DataManager.shared.remove(withId: contact.id) //Call DataManager to remove this contact by UUID
            loadContacts() //Refresh the table with updated data
        }
    }
}

extension ContactsViewController: UISearchBarDelegate 
{
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) //Called every time user types or deletes text in the search bar. It updates the searchResults array based on the current search text and reloads the table view to show the filtered results.
    {
        if searchText.isEmpty 
        {
            isSearching = false
            searchResults = allContacts
        } 
        else 
        {
            isSearching = true
            searchResults = DataManager.shared.search(query: searchText) //Call DataManager's search function to get contacts matching the name.
        }
        contactsTableView.reloadData()
    }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) //Called when user taps the "Search" button on the keyboard.
    {
        searchBar.resignFirstResponder() //Dismiss the keyboard when search is submitted.
    }
}

/*
extension ContactsViewController: CNContactPickerDelegate //Handles the contacts selected from iOS Contacts App.
{
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) 
    {
        var duplicateNames: [String] = [] //Tracks the names of contacts that were duplicate, to show in an alert.
        var limitHit = false //Tracks if the 5-contact limit was reached during import, to show an alert.

        for cnContact in contacts //Can select multiple contacts at once
        {
            let fullName = "\(cnContact.givenName) \(cnContact.familyName)".trimmingCharacters(in: .whitespaces) //Combines first+last name
            let phone = cnContact.phoneNumbers.first?.value.stringValue 

            guard !fullName.isEmpty else { continue } //Skip contacts without a name

            let person = MyPeople(name: fullName, phoneNumber: phone)
            let result = DataManager.shared.add(person) //Returns an enum indicating if the contact was added, a duplicate, or if the limit was reached.

            switch result {
            case .added:
                break //Contact added successfully, nothing to do
            case .duplicate:
                duplicateNames.append(fullName) 
                break //Track duplicate name for alert
            case .limitReached:
                limitHit = true //Stop processing more contacts if limit reached
                break
            }
            if limitHit 
            {
                break
            }
        }

        loadContacts()

        if limitHit 
        {
            showAlert(title: "Limit Reached",
                      message: "You can save up to \(DataManager.maxContacts) contacts. Some contacts were not added.")
        } else if !duplicateNames.isEmpty {
            let names = duplicateNames.joined(separator: ", ")
            showAlert(title: "Duplicate Skipped",
                      message: "\(names) already in your contacts.")
        }
    }
}
*/

class PersonCell: UITableViewCell //Custom table view cell to display a contact's avatar and name.
{
    @IBOutlet weak var avatarView: UIView!
    @IBOutlet weak var avatarLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    override func awakeFromNib() 
    {
        super.awakeFromNib()
    }
    func configure(with contact: MyPeople) 
    {
        avatarView.backgroundColor = contact.avatarColor
        avatarLabel.text = contact.avatarLetter
        nameLabel.text = contact.name
    }
}
