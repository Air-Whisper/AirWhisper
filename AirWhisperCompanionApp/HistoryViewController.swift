import UIKit
class HistoryViewController: UIViewController //Displays the message history grouped by date, showing contact name, message preview, and time. Handles empty state when no history is available.
{
    @IBOutlet weak var historyTableView: UITableView! // Table view to display message history
    @IBOutlet weak var emptyStateContainerView: UIView! // Container view for empty state
    private var sections: [HistorySection] = [] 
    override func viewDidLoad() 
    {
        super.viewDidLoad()
        loadHistoryData() //loads the message history
    }
    override func viewWillAppear(_ animated: Bool) //true=swipe transition, false=instant transition.
    {
        super.viewWillAppear(animated)
        loadHistoryData() 
    }
    private func loadHistoryData() 
    {
        sections = DataManager.shared.getGroupedHistory() //Fetch group history data from DataManager
        historyTableView.reloadData() //Refresh the table display with the new data.
        
        let isEmpty = sections.isEmpty
        emptyStateContainerView?.isHidden = !isEmpty // Show empty state if there are no history items, otherwise show the table view.
        historyTableView?.isHidden = isEmpty // Hide the table view when there are no history items to display.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTourIfNeeded()
    }

    // shows a guided tour on first app install to explain the history screen.
    private func showTourIfNeeded() {
        var steps: [CoachStep] = []
        if sections.isEmpty {
            steps.append(CoachStep(targetView: emptyStateContainerView, message: "No messages sent yet  - they'll appear here after you send one from the Watch.", position: .above))
        } else {
            steps.append(CoachStep(targetView: historyTableView, message: "Messages you've sent are grouped by date. Each row shows the contact, message, and time.", position: .above))
        }
        CoachMarkManager.shared.showTourIfNeeded(on: self, steps: steps, screenKey: "history")
    }
}
extension HistoryViewController: UITableViewDelegate, UITableViewDataSource 
{
    func numberOfSections(in tableView: UITableView) -> Int 
    {
        return sections.count
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int //Returns the number of rows in each section based on the count of items in that section.
    {
        return sections[section].items.count
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? //Returns the title for each section header, which is determined by the date grouping.
    {
        return sections[section].title
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell //Creates cells
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as! HistoryCell
        let item = sections[indexPath.section].items[indexPath.row]
        cell.configure(with: item)
        return cell
    }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat 
    {
        return 60
    }
}
class HistoryCell: UITableViewCell 
{
    @IBOutlet weak var avatarView: UIView!
    @IBOutlet weak var avatarLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    func configure(with item: HistoryItem) 
    {
        avatarView.backgroundColor = item.avatarColor
        avatarLabel.text = item.avatarLetter
        nameLabel.text = item.name
        messageLabel.text = item.message
        timeLabel.text = item.time
    }
}