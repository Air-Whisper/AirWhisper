//Edited by   on 2024-06-15.
//  view controller for managing quick speak phrases, allowing users to add, view, and delete their custom phrases.
import UIKit

class ManageQuickSpeakViewController: UIViewController {

    @IBOutlet weak var addNewPhraseLabel: UILabel!
    @IBOutlet weak var phraseTextField: UITextField!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var currentPhrasesLabel: UILabel!
    @IBOutlet weak var phrasesTableView: UITableView!
    
    private var phrases: [String] = [] // hold the current list of quick phrases for display in the table view
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        loadPhrases()
        NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: .dataDidChangeRemotely, object: nil) // notify this ViewController whenever the data changes remotely so it can update the UI accordingly.
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self) // stop listening for notifications when this ViewController is removed from memory to prevent memory leaks and unintended behavior.
    }
    
    @objc private func dataDidChange() { // objc is used here because this function is called by the NotificationCenter which requires the selector to be exposed to Objective-C runtime.
        DispatchQueue.main.async { [weak self] in
            self?.loadPhrases()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPhrases()
    }
    private func setupUI() {
        phraseTextField.applyStandardAuthStyle()
    }

    private func setupTableView() {
        phrasesTableView.delegate = self
        phrasesTableView.dataSource = self
        phrasesTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PhraseCell")
        phrasesTableView.estimatedRowHeight = 44
        phrasesTableView.rowHeight = UITableView.automaticDimension
    }
    
    private func loadPhrases() {
        phrases = DataManager.shared.getQuickPhraseTexts()
        phrasesTableView.reloadData()
    } // loads the current list of quick phrases from the DataManager shared instance and refreshes the table view to display them.
    
    //when action button it tapped 
    @IBAction func addButtonTapped(_ sender: UIButton) {
        guard let phrase = phraseTextField.text, !phrase.isEmpty else { return }
        // checks if the text field is not empty before proceeding to add the new phrase.
        let isFull = DataManager.shared.getQuickPhrases().count >= DataManager.maxPhrases
        // Checks if maximum phrase limit is reached.
        let added = DataManager.shared.addQuickPhraseIfUnique(text: phrase)
        // Adds phrase only if it doesn't already exist.
        
        if !added {
            // creates a shake animation when the input is not valid, duplicate or empty.
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.duration = 0.4
            animation.values = [-8, 8, -6, 6, -4, 4, 0]
            phraseTextField.layer.add(animation, forKey: "shake")
        }

        else if isFull {
            // if the list of phrtases is full and a new phrase is added then it replaces the least used phrase and shows an alert to inform the user about the replacement.
            let alert = UIAlertController(
                title: "Phrase Replaced",
                message: "Quick Speak is full (max \(DataManager.maxPhrases)). The least-used phrase was replaced.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
        
        loadPhrases()
        phraseTextField.text = "" // clears the text field after adding the phrase.
        phraseTextField.resignFirstResponder() // closes the keyboard after adding phrase.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTourIfNeeded()
    }

    // shows a guided tour on first app install to explain the quick speak screen.
    private func showTourIfNeeded() {
        let steps: [CoachStep] = [
            CoachStep(targetView: phraseTextField, message: "Type a new phrase you want quick access to.", position: .below),
            CoachStep(targetView: addButton, message: "Tap to save the phrase. Duplicates will shake the text field.", position: .below),
            CoachStep(targetView: phrasesTableView, message: "Your saved phrases appear here. Swipe left to delete. When full, the least-used phrase is auto-replaced.", position: .above)
        ]
        CoachMarkManager.shared.showTourIfNeeded(on: self, steps: steps, screenKey: "quickspeak")
    }
}

extension ManageQuickSpeakViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return phrases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PhraseCell", for: indexPath)
        cell.textLabel?.text = phrases[indexPath.row]
        cell.textLabel?.numberOfLines = 0
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return phrases[indexPath.row].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != "HELP"
    }// swipe to delete a row in the table view (except for 'Help').
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // removes the phrase from the DataManager and the local array.then update the table view.
            DataManager.shared.removeQuickPhrase(at: indexPath.row)
            phrases.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        }
    }
    
    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "Delete"
    }
}
