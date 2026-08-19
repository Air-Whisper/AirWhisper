import AVFoundation
import UIKit

// Top: looping HowToUse3Video from the carousel card
// Body: accurate steps drawn directly from PhraseManager + QuickSpeakView logic

class QuickPhrasesHowToUseViewController: UIViewController {

    @IBOutlet weak var videoContainer: UIView!
    @IBOutlet weak var stepsStackView: UIStackView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var managePhrasesCTAButton: UIButton!

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Quick Phrases - How to Use"
        view.backgroundColor = UIColor.systemGroupedBackground
        setupVideo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = videoContainer?.bounds ?? .zero
        drawConnectingLines()
    }

    private func drawConnectingLines() {
        stepsStackView.layer.sublayers?.filter { $0.name == "stepLine" }.forEach { $0.removeFromSuperlayer() }
        
        let steps = stepsStackView.arrangedSubviews
        guard steps.count > 1 else { return }
        
        for i in 0..<(steps.count - 1) {
            let currentStep = steps[i]
            let nextStep = steps[i + 1]
            
            // QPX steps are UIStackViews where the first arrangedSubview is the number circle container
            guard let currentStack = currentStep as? UIStackView, let currentCircle = currentStack.arrangedSubviews.first else { continue }
            guard let nextStack = nextStep as? UIStackView, let _ = nextStack.arrangedSubviews.first else { continue }
            
            let startFrame = stepsStackView.convert(currentCircle.bounds, from: currentCircle)
            let currentStepFrame = stepsStackView.convert(currentStep.bounds, from: currentStep)
            
            let path = UIBezierPath()
            path.move(to: CGPoint(x: startFrame.midX, y: startFrame.maxY))
            path.addLine(to: CGPoint(x: startFrame.midX, y: currentStepFrame.maxY))
            
            let lineLayer = CAShapeLayer()
            lineLayer.path = path.cgPath
            lineLayer.strokeColor = UIColor(red: 0.114, green: 0.631, blue: 0.949, alpha: 0.25).cgColor
            lineLayer.lineWidth = 2.0
            lineLayer.name = "stepLine"
            
            stepsStackView.layer.insertSublayer(lineLayer, at: 0)
        }
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
        let name = "HowToUse3Video"
        var url: URL?
        if let u = Bundle.main.url(forResource: name, withExtension: "mp4") { url = u }
        else if let u = Bundle.main.url(forResource: name, withExtension: "mov") { url = u }
        else if let asset = NSDataAsset(name: name) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".mp4")
            try? asset.data.write(to: tmp, options: .atomic)
            url = tmp
        }
        guard let videoURL = url else { return }

        let item = AVPlayerItem(url: videoURL)
        let qp = AVQueuePlayer()
        let loop = AVPlayerLooper(player: qp, templateItem: item)
        qp.isMuted = true
        qp.play()

        let layer = AVPlayerLayer(player: qp)
        layer.videoGravity = .resizeAspect
        layer.frame = container.bounds
        container.layer.addSublayer(layer)
        container.viewWithTag(888)?.isHidden = true

        self.player = qp
        self.looper = loop
        self.playerLayer = layer
    }

    @IBAction func managePhrasesTapped(_ sender: UIButton) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        let vc = sb.instantiateViewController(withIdentifier: "ManageQuickSpeakViewController")
        navigationController?.pushViewController(vc, animated: true)
    }
}
