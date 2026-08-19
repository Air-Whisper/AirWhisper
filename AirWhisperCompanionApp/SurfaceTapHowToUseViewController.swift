import AVFoundation
import UIKit

// Structure: Video → What is it? → Steps (no CTA button)

class SurfaceTapHowToUseViewController: UIViewController {

    @IBOutlet weak var videoContainer: UIView!
    @IBOutlet weak var stepsStackView: UIStackView!
    @IBOutlet weak var contentView: UIView!

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Surface Tap - How to Use"
        view.backgroundColor = UIColor.systemGroupedBackground
        setupVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoContainer?.bounds ?? .zero
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        player?.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.pause()
    }

    private func setupVideo() {
        guard let container = videoContainer else { return }
        let name = "HowToUse4Video"
        var url: URL?
        if let u = Bundle.main.url(forResource: name, withExtension: "mp4") { url = u }
        else if let u = Bundle.main.url(forResource: name, withExtension: "mov") { url = u }
        else if let asset = NSDataAsset(name: name) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".mp4")
            try? asset.data.write(to: tmp, options: .atomic); url = tmp
        }
        guard let videoURL = url else { return }

        let item = AVPlayerItem(url: videoURL)
        let qp = AVQueuePlayer()
        let loop = AVPlayerLooper(player: qp, templateItem: item)
        qp.isMuted = true; qp.play()

        let layer = AVPlayerLayer(player: qp)
        layer.videoGravity = .resizeAspect
        layer.frame = container.bounds
        container.layer.insertSublayer(layer, at: 0)
        container.viewWithTag(888)?.isHidden = true

        self.player = qp; self.looper = loop; self.playerLayer = layer
    }
}
