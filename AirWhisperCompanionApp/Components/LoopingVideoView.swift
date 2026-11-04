import SwiftUI
import AVFoundation
import UIKit

/// A looping, muted video view backed by `AVQueuePlayer` + `AVPlayerLooper`.
///
/// Ports the video pattern used across the app (How-To screens, onboarding):
/// - resolution order: bundled mp4 → bundled mov → NSDataAsset written to a temp file
/// - muted playback
/// - configurable video gravity
struct LoopingVideoView: UIViewRepresentable {

    let resourceName: String
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var isPlaying = true

    func makeUIView(context: Context) -> PlayerContainerView {
        PlayerContainerView()
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // Rebuild the player if the resource changed (e.g. onboarding page flip).
        if uiView.currentResource != resourceName {
            uiView.configure(resourceName: resourceName, gravity: videoGravity)
        }
        uiView.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.stop()
    }
}

/// Container that hosts the AVPlayerLayer.
final class PlayerContainerView: UIView {

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    var currentResource: String?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    func configure(resourceName: String, gravity: AVLayerVideoGravity) {
        stop()
        currentResource = resourceName

        guard let url = HowToVideoURL.resolve(named: resourceName) else { return }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true

        let layer = self.layer as? AVPlayerLayer
        layer?.player = queuePlayer
        layer?.videoGravity = gravity

        player = queuePlayer
        looper = playerLooper
        playerLayer = layer
    }

    func setPlaying(_ isPlaying: Bool) {
        guard isPlaying else {
            player?.pause()
            return
        }
        player?.play()
    }

    func stop() {
        player?.pause()
        (layer as? AVPlayerLayer)?.player = nil
        player = nil
        looper = nil
        playerLayer = nil
    }
}

/// Ports the `videoURL(named:)` resolution helper duplicated across the
/// How-To view controllers.
enum HowToVideoURL {

    static func resolve(named resourceName: String) -> URL? {
        // 1. Bundled mp4
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: "mp4") {
            return bundledURL
        }
        // 2. Bundled mov
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: "mov") {
            return bundledURL
        }
        // 3. NSDataAsset fallback: write to temp directory, then play from there
        guard let dataAsset = NSDataAsset(name: resourceName) else { return nil }
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
}
