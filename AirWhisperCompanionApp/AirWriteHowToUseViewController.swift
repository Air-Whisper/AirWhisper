import AVFoundation
import UIKit

class AirWriteHowToUseViewController: UIViewController {

    @IBOutlet weak var videoContainer: UIView!
    @IBOutlet weak var stepsStackView: UIStackView!
    @IBOutlet weak var contentView: UIView!

    private var featurePlayer: AVQueuePlayer?
    private var featureLooper: AVPlayerLooper?
    private var featurePlayerLayer: AVPlayerLayer?

    private let letters: [String] = (65...90).map { String(UnicodeScalar($0)) }
    private var letterPlayers: [AVQueuePlayer] = []
    private var letterLoopers: [AVPlayerLooper] = []
    private var letterPlayerLayers: [AVPlayerLayer] = []
    private var currentLetterIndex = 0
    @IBOutlet weak var letterLabel: UILabel!
    @IBOutlet weak var videoContainerView: UIView!
    @IBOutlet weak var leftChevronButton: UIButton!
    @IBOutlet weak var rightChevronButton: UIButton!
    @IBOutlet weak var letterCarouselCard: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AirWrite - How to Use"
        view.backgroundColor = UIColor.systemGroupedBackground
        letterCarouselCard.layer.cornerRadius = 20
        letterCarouselCard.layer.shadowColor = UIColor.black.cgColor
        letterCarouselCard.layer.shadowOpacity = 0.07
        letterCarouselCard.layer.shadowOffset = CGSize(width: 0, height: 3)
        letterCarouselCard.layer.shadowRadius = 8
        letterCarouselCard.clipsToBounds = false
        videoContainerView.backgroundColor = .white
        setupFeatureVideo()
        setupLetterPlayers()
        showLetter(at: 0, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        featurePlayerLayer?.frame = videoContainer?.bounds ?? .zero
        if let container = videoContainerView {
            for layer in letterPlayerLayers { layer.frame = container.bounds }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        featurePlayer?.play()
        playCurrentLetter()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        featurePlayer?.pause()
        letterPlayers.forEach { $0.pause() }
    }

    private func setupFeatureVideo() {
        guard let container = videoContainer else { return }
        guard let url = videoURL(named: "HowToUse1Video") else { return }

        let item = AVPlayerItem(url: url)
        let qp = AVQueuePlayer()
        let loop = AVPlayerLooper(player: qp, templateItem: item)
        qp.isMuted = true
        qp.play()

        let layer = AVPlayerLayer(player: qp)
        layer.videoGravity = .resizeAspect
        layer.frame = container.bounds
        container.layer.insertSublayer(layer, at: 0)
        container.viewWithTag(888)?.isHidden = true

        featurePlayer = qp; featureLooper = loop; featurePlayerLayer = layer
    }

    private func setupLetterPlayers() {
        for letter in letters {
            if let url = videoURL(named: letter) {
                let item = AVPlayerItem(url: url)
                let player = AVQueuePlayer()
                let looper = AVPlayerLooper(player: player, templateItem: item)
                player.isMuted = true
                player.defaultRate = 1.5
                let layer = AVPlayerLayer(player: player); layer.videoGravity = .resizeAspect
                letterPlayers.append(player); letterLoopers.append(looper); letterPlayerLayers.append(layer)
            } else {
                let player = AVQueuePlayer()
                letterPlayers.append(player)
                letterLoopers.append(AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: URL(fileURLWithPath: ""))))
                letterPlayerLayers.append(AVPlayerLayer(player: player))
            }
        }
    }

    private func videoURL(named name: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: "mp4") { return u }
        if let u = Bundle.main.url(forResource: name, withExtension: "mov") { return u }
        guard let asset = NSDataAsset(name: name) else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".mp4")
        try? asset.data.write(to: tmp, options: .atomic); return tmp
    }

    @IBAction private func prevLetter(_ sender: UIButton) {
        showLetter(at: (currentLetterIndex - 1 + letters.count) % letters.count, animated: true)
    }

    @IBAction private func nextLetter(_ sender: UIButton) {
        showLetter(at: (currentLetterIndex + 1) % letters.count, animated: true)
    }

    private func showLetter(at index: Int, animated: Bool) {
        guard let container = videoContainerView else { return }
        letterPlayers[currentLetterIndex].pause()
        letterPlayerLayers[currentLetterIndex].removeFromSuperlayer()
        currentLetterIndex = index
        let letter = letters[index]
        let hasVideo = videoURL(named: letter) != nil
        container.viewWithTag(999)?.isHidden = hasVideo
        let layer = letterPlayerLayers[index]; layer.frame = container.bounds
        container.layer.addSublayer(layer)
        if animated {
            UIView.transition(with: letterLabel, duration: 0.18, options: .transitionCrossDissolve) {
                self.letterLabel.text = letter
            }
        } else {
            letterLabel.text = letter
        }
        playCurrentLetter(); updateChevrons()
    }

    private func playCurrentLetter() {
        guard currentLetterIndex < letterPlayers.count else { return }
        letterPlayers[currentLetterIndex].play()
    }

    private func updateChevrons() {
        leftChevronButton?.alpha  = currentLetterIndex == 0 ? 0.3 : 1.0
        rightChevronButton?.alpha = currentLetterIndex == letters.count - 1 ? 0.3 : 1.0
    }
}
