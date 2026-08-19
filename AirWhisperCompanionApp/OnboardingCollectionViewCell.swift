//
//  OnboardingCollectionViewCell.swift
//  AirWhisperCompanionApp
//
//  Created by GEU on 31/03/26.
//

import AVFoundation
import UIKit

class OnboardingCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var bottomView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?
    private var baseImageOffsetY: CGFloat = 0
    private var hasAnimatedEntrance = false

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = imageView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetVideoPlayback()
        hasAnimatedEntrance = false
        baseImageOffsetY = 0
        imageView.transform = .identity
        bottomView.transform = .identity
        titleLabel.transform = .identity
        descriptionLabel.transform = .identity
        imageView.alpha = 1
        bottomView.alpha = 1
        titleLabel.alpha = 1
        descriptionLabel.alpha = 1
        imageView.image = nil
    }

    func configureCell(data: OnboardingItem) {
        titleLabel.text = data.title
        descriptionLabel.text = data.description
        baseImageOffsetY = videoVerticalOffsetY(for: data.video)
        configureVideo(named: data.video)
    }

    func applyRestingState() {
        hasAnimatedEntrance = true
        imageView.alpha = 1
        bottomView.alpha = 1
        titleLabel.alpha = 1
        descriptionLabel.alpha = 1
        imageView.transform = imageTransform(yOffset: 0)
        bottomView.transform = .identity
        titleLabel.transform = .identity
        descriptionLabel.transform = .identity
    }

    func prepareForEntranceAnimation() {
        hasAnimatedEntrance = false
        imageView.alpha = 0
        bottomView.alpha = 1
        titleLabel.alpha = 0
        descriptionLabel.alpha = 0

        imageView.transform = imageTransform(yOffset: 18)
        bottomView.transform = .identity
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 18)
        descriptionLabel.transform = CGAffineTransform(translationX: 0, y: 14)
    }

    func animateEntranceIfNeeded(completion: (() -> Void)? = nil) {
        guard !hasAnimatedEntrance else { return }
        hasAnimatedEntrance = true

        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.35,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.imageView.alpha = 1
            self.bottomView.alpha = 1
            self.imageView.transform = self.imageTransform(yOffset: 0)
            self.bottomView.transform = .identity
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0.12,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
        }

        UIView.animate(
            withDuration: 0.34,
            delay: 0.24,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.descriptionLabel.alpha = 1
            self.descriptionLabel.transform = .identity
        } completion: { _ in
            completion?()
        }
    }

    func transitionContent(to data: OnboardingItem, completion: (() -> Void)? = nil) {
        imageView.layer.removeAllAnimations()
        titleLabel.layer.removeAllAnimations()
        descriptionLabel.layer.removeAllAnimations()

        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.imageView.alpha = 0
            self.titleLabel.alpha = 0
            self.descriptionLabel.alpha = 0
        } completion: { _ in
            self.configureCell(data: data)
            self.prepareForEntranceAnimation()
            self.layoutIfNeeded()
            self.animateEntranceIfNeeded(completion: completion)
        }
    }

    private func configureVideo(named resourceName: String) {
        resetVideoPlayback()
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

        self.player = player
        self.playerLooper = looper
        self.playerLayer = playerLayer

        player.play()
    }

    private func resetVideoPlayback() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        playerLayer = nil
        playerLooper = nil
    }

    private func videoVerticalOffsetY(for resourceName: String) -> CGFloat {
        switch resourceName {
        case "HowToUse3Video", "HowToUse4Video":
            return -18
        default:
            return 0
        }
    }

    private func imageTransform(yOffset: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: 0, y: baseImageOffsetY + yOffset)
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
}
