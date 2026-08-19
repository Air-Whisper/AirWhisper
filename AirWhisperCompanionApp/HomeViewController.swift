import AVFoundation
import UIKit

class HomeViewController: UIViewController, UIScrollViewDelegate {
    // this creates a screen controller for the home screen.

    @IBOutlet weak var howToHeaderView: UIView!
    @IBOutlet weak var howToHeaderCardView: UIView!
    @IBOutlet weak var howToChevronImageView: UIImageView!
    @IBOutlet weak var carouselContainerView: UIView!
    @IBOutlet weak var carouselBackgroundCardView: UIView!
    @IBOutlet weak var carouselScrollView: UIScrollView! 
    @IBOutlet weak var carouselPageControl: UIPageControl!
    @IBOutlet weak var howToUseImageView1: UIImageView!
    @IBOutlet weak var howToUseImageView2: UIImageView!
    @IBOutlet weak var howToUseImageView3: UIImageView!
    @IBOutlet weak var howToUseImageView4: UIImageView!
    @IBOutlet weak var sensitivitySliderControl: UISlider!
    @IBOutlet weak var voiceGuidanceSwitch: UISwitch!
    @IBOutlet weak var tapDetectorSwitch: UISwitch!
    @IBOutlet weak var recalibrateLabel: UILabel!

    // Outlets for the 4 how-to carousel card inner views (used to attach tap gestures)
    @IBOutlet weak var cardInnerView1: UIView!   // AirWrite
    @IBOutlet weak var cardInnerView2: UIView!   // OrientWrite
    @IBOutlet weak var cardInnerView3: UIView!   // Quick Phrases
    @IBOutlet weak var cardInnerView4: UIView!   // Surface Tap

    private var settingsSyncWorkItem: DispatchWorkItem? // debouncing the setting sync to avoid flooding the system with updates when changes appear in settings.
    private let settingsSyncDebounceInterval: TimeInterval = 0.3 // debouncing interval.
    private var tutorialPlayers: [AVQueuePlayer] = []
    private var tutorialPlayerLayers: [AVPlayerLayer] = []
    private var tutorialLoopers: [AVPlayerLooper] = []
    private var isHowToExpanded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        loadWatchSettings()
        setupHowToVideos()
        setHowToExpanded(false, animated: false)
        configureAccessibility()
        setupCardTapGestures()
        setupRecalibrateLabel()
    }
    // called when view controller is first loaded, and then populates the watch settings in the ui.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        loadWatchSettings()
        if isHowToExpanded {
            resumeHowToVideos()
        }
    }
    // called every time the view is about to appear, and then hides the navigation bar for a more immersive experience and refreshes the watch settings.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTourIfNeeded()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHowToVideoFrames()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        flushPendingSettingsSync()
        pauseHowToVideos()
    }
    // called every time the view is about to disappear, and then shows the navigation bar again and flushes any pending settings sync to ensure that any changes made by the user are saved before leaving the screen.
    private func loadWatchSettings() {
        if let settings = DataManager.shared.getWatchSettings() {
            sensitivitySliderControl.value = settings.sensitivity
            voiceGuidanceSwitch.isOn = settings.voiceGuidance
            tapDetectorSwitch.isOn = settings.tapDetectorEnabled
        } else {
            sensitivitySliderControl.value = WatchSettings.defaultValue
            voiceGuidanceSwitch.isOn = false
            tapDetectorSwitch.isOn = false
        }
        updateSettingsAccessibilityValues()
    }
    // this function loads the watch settings from the DataManager and updates all controls in the UI. If there are no saved settings, it sets the controls to their default values.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == carouselScrollView {
            let pageIndex = round(scrollView.contentOffset.x / scrollView.frame.width)
            carouselPageControl.currentPage = Int(pageIndex)
        }
    }

    @IBAction func howToToggleButtonTapped(_ sender: UIButton) {
        setHowToExpanded(!isHowToExpanded, animated: true)
    }

    // MARK: - Card Tap Navigation

    /// Attaches UITapGestureRecognizer to each of the 4 carousel cards.
    /// Cards are matched by their imageView outlets (cardInnerView1-4 are optional;
    /// if not connected in IB we fall back to imageView parent chains).
    private func setupCardTapGestures() {
        // Each card inner view needs userInteractionEnabled = YES to receive taps
        // alongside the scroll view. We attach recognizers to the imageView's
        // superview (the cardInner view) so they don't block scrolling.
        let pairs: [(UIView?, Selector)] = [
            (howToUseImageView1?.superview, #selector(openAirWriteHowTo)),
            (howToUseImageView2?.superview, #selector(openOrientWriteHowTo)),
            (howToUseImageView3?.superview, #selector(openQuickPhrasesHowTo)),
            (howToUseImageView4?.superview, #selector(openSurfaceTapHowTo)),
        ]
        for (cardView, action) in pairs {
            guard let cardView else { continue }
            cardView.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: action)
            cardView.addGestureRecognizer(tap)
        }
    }

    @objc private func openAirWriteHowTo() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "AirWriteHowToUseVC") as? AirWriteHowToUseViewController {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc private func openOrientWriteHowTo() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "OrientWriteHowToUseVC") as? OrientWriteHowToUseViewController {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc private func openQuickPhrasesHowTo() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "QuickPhrasesHowToUseVC") as? QuickPhrasesHowToUseViewController {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @objc private func openSurfaceTapHowTo() {
        if let vc = storyboard?.instantiateViewController(withIdentifier: "SurfaceTapHowToUseVC") as? SurfaceTapHowToUseViewController {
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    @IBAction func sensitivitySliderChanged(_ sender: UISlider) {
        updateSettingsAccessibilityValues()
        scheduleDebouncedSettingsSync()
    }
    // when sensitivity slider is changed, we call the sync but with debouncing to avoid too many updates in a short time.
    @IBAction func voiceGuidanceSwitchChanged(_ sender: UISwitch) {
        updateSettingsAccessibilityValues()
        scheduleDebouncedSettingsSync()
    }
    // when voice guidance switch is changed, we call the debounced sync.
    
    @IBAction func tapDetectorSwitchChanged(_ sender: UISwitch) {
        updateSettingsAccessibilityValues()
        scheduleDebouncedSettingsSync()
    }
    // when tap detector switch is changed, we call the debounced sync.
    
    private func scheduleDebouncedSettingsSync() {
        settingsSyncWorkItem?.cancel()
    // if there is already a pending sync, we cancel it to reset the debounce timer.
        let sensitivity = sensitivitySliderControl.value
        let voiceGuidance = voiceGuidanceSwitch.isOn
        let tapDetectorEnabled = tapDetectorSwitch.isOn
    // capture the current values of controls to use in the sync operation.
        let workItem = DispatchWorkItem {
            DataManager.shared.updateSensitivity(sensitivity)
            DataManager.shared.updateVoiceGuidance(voiceGuidance)
            DataManager.shared.updateTapDetectorEnabled(tapDetectorEnabled)
        }
    // create a new work item that will perform the settings update after the debounce interval.
        settingsSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsSyncDebounceInterval, execute: workItem)
    // schedule the work item to be executed after the debounce interval, allowing for any rapid changes to be combined into a single update operation.
    }

    private func configureAccessibility() {
        sensitivitySliderControl.accessibilityLabel = "Watch cursor sensitivity"
        sensitivitySliderControl.accessibilityHint = "Adjusts how responsive the Apple Watch cursor is."

        voiceGuidanceSwitch.accessibilityLabel = "Voice guidance"
        voiceGuidanceSwitch.accessibilityHint = "Toggles spoken feedback on the Apple Watch."

        tapDetectorSwitch.accessibilityLabel = "Tap detector"
        tapDetectorSwitch.accessibilityHint = "Toggles surface-tap gesture detection on the Apple Watch."

        updateSettingsAccessibilityValues()
    }

    private func updateSettingsAccessibilityValues() {
        let sensitivity = Int(round(sensitivitySliderControl.value))
        sensitivitySliderControl.accessibilityValue = "\(sensitivity) percent"
        voiceGuidanceSwitch.accessibilityValue = voiceGuidanceSwitch.isOn ? "On" : "Off"
        tapDetectorSwitch.accessibilityValue = tapDetectorSwitch.isOn ? "On" : "Off"
    }

    private func flushPendingSettingsSync() {
        guard let pending = settingsSyncWorkItem else { return }
        pending.cancel()
        settingsSyncWorkItem = nil
        DataManager.shared.updateSensitivity(
            sensitivitySliderControl.value
        )
        DataManager.shared.updateVoiceGuidance(
            voiceGuidanceSwitch.isOn
        )
        DataManager.shared.updateTapDetectorEnabled(
            tapDetectorSwitch.isOn
        )
    }
    // checking if there is a pending sync for settings, if there is then we cancel it and immediately perform the sync to ensure that any changes made by the user are saved before leaving the screen.

    private func setupHowToVideos() {
        configureHowToVideo(named: "HowToUse1Video", in: howToUseImageView1)
        configureHowToVideo(named: "HowToUse2Video", in: howToUseImageView2)
        configureHowToVideo(named: "HowToUse3Video", in: howToUseImageView3)
        configureHowToVideo(named: "HowToUse4Video", in: howToUseImageView4)
    }

    private func configureHowToVideo(named resourceName: String, in imageView: UIImageView) {
        guard let url = howToVideoURL(named: resourceName) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let playerLayer = AVPlayerLayer(player: player)

        player.isMuted = true
        
        if resourceName == "HowToUse2Video" {
            playerLayer.videoGravity = .resizeAspectFill
        } else {
            playerLayer.videoGravity = .resizeAspect
        }
        


        playerLayer.frame = imageView.bounds

        imageView.image = nil
        imageView.layer.addSublayer(playerLayer)

        tutorialPlayers.append(player)
        tutorialLoopers.append(looper)
        tutorialPlayerLayers.append(playerLayer)

        player.play()
    }

    private func updateHowToVideoFrames() {
        let containers = [howToUseImageView1, howToUseImageView2, howToUseImageView3, howToUseImageView4]

        for (playerLayer, container) in zip(tutorialPlayerLayers, containers) {
            playerLayer.frame = container?.bounds ?? .zero
        }
    }

    private func resumeHowToVideos() {
        tutorialPlayers.forEach { $0.play() }
    }

    private func pauseHowToVideos() {
        tutorialPlayers.forEach { $0.pause() }
    }

    private func setHowToExpanded(_ expanded: Bool, animated: Bool) {
        isHowToExpanded = expanded
        let updates = {
            self.carouselContainerView.alpha = expanded ? 1.0 : 0.0
            self.howToChevronImageView.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.down")
            self.updateHowToCardAppearance(for: expanded)
            self.view.layoutIfNeeded()
        }

        if expanded {
            carouselContainerView.isHidden = false
            updateHowToVideoFrames()
            resumeHowToVideos()
        } else {
            pauseHowToVideos()
        }

        if animated {
            UIView.animate(withDuration: 0.22, animations: updates) { _ in
                self.carouselContainerView.isHidden = !expanded
            }
        } else {
            updates()
            carouselContainerView.isHidden = !expanded
        }
    }

    private func updateHowToCardAppearance(for expanded: Bool) {
        if expanded {
            howToHeaderCardView.layer.cornerRadius = 24
            howToHeaderCardView.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner
            ]
        } else {
            howToHeaderCardView.layer.cornerRadius = 18
            howToHeaderCardView.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
        }

        carouselBackgroundCardView.layer.maskedCorners = [
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner
        ]
    }

    private func howToVideoURL(named resourceName: String) -> URL? {
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            return bundledURL
        }

        guard let dataAsset = NSDataAsset(name: resourceName) else {
            return nil
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(resourceName)
            .appendingPathExtension("mp4")

        do {
            try dataAsset.data.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        } catch {
            return nil
        }
    }

    // shows a guided tour on first app install to explain the home screen controls.
    private func showTourIfNeeded() {
        let steps: [CoachStep] = [
            CoachStep(targetView: howToHeaderView, message: "Tap to expand or collapse the How to Use tips.", position: .below),
            CoachStep(targetView: sensitivitySliderControl, message: "Drag to adjust watch cursor sensitivity. Higher = more responsive.", position: .above),
            CoachStep(targetView: voiceGuidanceSwitch, message: "Toggle to enable/disable spoken feedback on your Apple Watch.", position: .above),
            CoachStep(targetView: tapDetectorSwitch, message: "Enable to use surface-tap gestures instead of touch on Apple Watch.", position: .above)
        ]
        CoachMarkManager.shared.showTourIfNeeded(on: self, steps: steps, screenKey: "home")
    }

    private func setupRecalibrateLabel() {
        guard let label = recalibrateLabel else { return }
        let fullText = label.text ?? "Recalibrate tap detection from your profile"
        let attributed = NSMutableAttributedString(string: fullText)
        let linkRange = (fullText as NSString).range(of: "Recalibrate")
        attributed.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: linkRange)
        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: linkRange)
        label.attributedText = attributed
        label.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleRecalibrateTap(_:)))
        label.addGestureRecognizer(tap)
    }

    @objc private func handleRecalibrateTap(_ gesture: UITapGestureRecognizer) {
        performSegue(withIdentifier: "seg-show-profile", sender: nil)
    }

    @IBAction private func profileButtonTapped(_ sender: UIButton) {
        performSegue(withIdentifier: "seg-show-profile", sender: sender)
    }
}
