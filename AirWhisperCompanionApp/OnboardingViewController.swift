//
//  OnboardingViewController.swift
//  AirWhisperCompanionApp
//
//  Created by GEU on 27/03/26.
//

import AVFoundation
import UIKit

class OnboardingViewController: UIViewController {

    @IBOutlet weak var arcImageView: UIImageView!
    @IBOutlet weak var mediaImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var pageControl: UIPageControl!
    @IBOutlet weak var skipButton: UIButton!

    @IBAction func handleSwipeRight(_ sender: UISwipeGestureRecognizer)
    {
        goToPreviousPage()
    }
    @IBAction func handleSwipeLeft(_ sender: UISwipeGestureRecognizer)
    {
        goToNextPage()
    }
    
    private let onboardingScreens = OnboardingItem.items
    private var currentPage: Int = 0
    private var isTransitioning = false

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AVPlayerLooper?

    override func viewDidLoad()
    {
        super.viewDidLoad()
        updateSkipButton(for: 0)
        loadContent(for: onboardingScreens[0], animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = mediaImageView.bounds
    }

    private func goToNextPage() {
        guard !isTransitioning else { return }
        guard currentPage < onboardingScreens.count - 1 else { return }

        currentPage += 1
        let data = onboardingScreens[currentPage]
        transitionContent(to: data)
        pageControl.currentPage = currentPage
        updateSkipButton(for: currentPage)
    }

    private func goToPreviousPage() {
        guard !isTransitioning else { return }
        guard currentPage > 0 else { return }

        currentPage -= 1
        let data = onboardingScreens[currentPage]
        transitionContent(to: data)
        pageControl.currentPage = currentPage
        updateSkipButton(for: currentPage)
    }
    private func updateSkipButton(for page: Int)
    {
        let isLastPage = page == onboardingScreens.count - 1
        let title = isLastPage ? "Next" : "Skip"
        skipButton.setTitle(title, for: .normal)
    }

    @IBAction func skipButtonTapped(_ sender: UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if let loginVC = storyboard.instantiateViewController(withIdentifier: "LoginViewController") as? MainAuthViewController {
            if let window = view.window {
                window.rootViewController = loginVC
                window.makeKeyAndVisible()
            }
        }
    }


    private func loadContent(for data: OnboardingItem, animated: Bool) {
        resetVideoPlayback()

        titleLabel.text = data.title
        descriptionLabel.text = data.description

        let offsetY = videoVerticalOffsetY(for: data.video)
        mediaImageView.transform = CGAffineTransform(translationX: 0, y: offsetY)

        configureVideo(named: data.video)
    }

    private func transitionContent(to data: OnboardingItem) {
        isTransitioning = true

        mediaImageView.layer.removeAllAnimations()
        titleLabel.layer.removeAllAnimations()
        descriptionLabel.layer.removeAllAnimations()

        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.mediaImageView.alpha = 0
            self.titleLabel.alpha = 0
            self.descriptionLabel.alpha = 0
        } completion: { _ in
            self.loadContent(for: data, animated: true)
            self.prepareForEntranceAnimation()
            self.view.layoutIfNeeded()

            self.animateEntrance {
                self.isTransitioning = false
            }
        }
    }

    private func prepareForEntranceAnimation() {
        mediaImageView.alpha = 0
        titleLabel.alpha = 0
        descriptionLabel.alpha = 0

        let baseY = videoVerticalOffsetY(for: onboardingScreens[currentPage].video)
        mediaImageView.transform = CGAffineTransform(translationX: 0, y: baseY + 18)
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 18)
        descriptionLabel.transform = CGAffineTransform(translationX: 0, y: 14)
    }

    private func animateEntrance(completion: (() -> Void)? = nil) {
        let baseY = videoVerticalOffsetY(for: onboardingScreens[currentPage].video)

        UIView.animate(
            withDuration: 0.8,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.2,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.mediaImageView.alpha = 1
            self.mediaImageView.transform = CGAffineTransform(translationX: 0, y: baseY)
        }

        UIView.animate(
            withDuration: 0.5,
            delay: 0.2,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
        }

        UIView.animate(
            withDuration: 0.5,
            delay: 0.4,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.descriptionLabel.alpha = 1
            self.descriptionLabel.transform = .identity
        } completion: { _ in
            completion?()
        }
    }

    private func configureVideo(named resourceName: String) {
        resetVideoPlayback()
        guard let url = howToVideoURL(named: resourceName) else { return }

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

        playerLayer.frame = mediaImageView.bounds
        mediaImageView.image = nil
        mediaImageView.layer.addSublayer(playerLayer)

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
