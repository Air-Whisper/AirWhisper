import SwiftUI
import AVFoundation
import UIKit

struct AirWriteHowToView: View {
    @State private var currentLetterIndex = 0
    @State private var isVisible = false
    @State private var letterVideoAvailability: [String: Bool] = [:]

    private let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }
    private let accentColor = Color(red: 0.114, green: 0.631, blue: 0.949, opacity: 1)

    private let steps: [(title: String, detail: String)] = [
        (
            "Wear on your LEFT hand",
            "The IMU model is trained specifically on left-hand movements. Wearing the watch on your right hand will result in incorrect predictions."
        ),
        (
            "Draw the letter in the air",
            "Trace the letter shape with your arm in one smooth motion. Draw exactly as you would if the air were your writing canvas."
        ),
        (
            "Confidence threshold for accepted letters",
            "The on-device Core ML model scores each prediction. Only letters meeting the confidence threshold are added and spoken aloud. If the model is unsure, the result is silently dropped needing you to draw the letter again."
        )
    ]

    private var currentLetter: String {
        letters[currentLetterIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ZStack {
                    Color.white
                    LoopingVideoView(
                        resourceName: "HowToUse1Video",
                        videoGravity: .resizeAspect,
                        isPlaying: isVisible
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 16) {
                    Text("What is AirWrite?")
                        .font(.system(size: 20, weight: .bold))

                    Text("AirWrite lets you compose messages by drawing letters in the air using broad arm movements—no typing or screen touch required.")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("How to Use")
                        .font(.system(size: 20, weight: .bold))

                    ForEach(steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(accentColor, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(steps[index].title)
                                    .font(.system(size: 15))

                                Text(steps[index].detail)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Design.secondaryLabel)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .background(alignment: .topLeading) {
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(accentColor.opacity(0.25))
                                    .frame(width: 2, height: max(0, geometry.size.height - 32))
                                    .offset(x: 15, y: 32)
                            }
                        }
                    }

                    Color.clear.frame(height: 20)

                    Text("Letter Reference")
                        .font(.system(size: 20, weight: .bold))

                    Text("Browse every letter to see the exact wrist motion used to train the model.")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        ZStack {
                            Text(currentLetter)
                                .id(currentLetter)
                                .font(.system(size: 28, weight: .bold))
                                .transition(.opacity)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .padding(.top, 16)

                        ZStack {
                            Color.white
                            if letterVideoAvailability[currentLetter] == false {
                                Text("Video coming soon")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                            } else {
                                AirWriteLetterVideoView(resourceName: currentLetter, isPlaying: isVisible)
                                    .id(currentLetter)
                            }
                        }
                        .frame(height: 190)
                        .padding(.top, 10)

                        HStack {
                            Button(action: showPreviousLetter) {
                                Image(systemName: "chevron.left")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accentColor)
                            .opacity(currentLetterIndex == 0 ? 0.3 : 1)

                            Spacer()

                            Button(action: showNextLetter) {
                                Image(systemName: "chevron.right")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(accentColor)
                            .opacity(currentLetterIndex == letters.count - 1 ? 0.3 : 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    }
                    .background(Design.background, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.groupedBackground)
        .navigationTitle("AirWrite - How to Use")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadLetterVideoAvailability()
            isVisible = true
        }
        .onDisappear {
            isVisible = false
        }
    }

    private func loadLetterVideoAvailability() {
        guard letterVideoAvailability.isEmpty else { return }
        letterVideoAvailability = Dictionary(
            uniqueKeysWithValues: letters.map { letter in
                (letter, HowToVideoURL.resolve(named: letter) != nil)
            }
        )
    }

    private func showPreviousLetter() {
        withAnimation(.easeInOut(duration: 0.18)) {
            currentLetterIndex = (currentLetterIndex - 1 + letters.count) % letters.count
        }
    }

    private func showNextLetter() {
        withAnimation(.easeInOut(duration: 0.18)) {
            currentLetterIndex = (currentLetterIndex + 1) % letters.count
        }
    }
}

private struct AirWriteLetterVideoView: UIViewRepresentable {
    let resourceName: String
    let isPlaying: Bool

    func makeUIView(context: Context) -> AirWriteLetterPlayerView {
        let view = AirWriteLetterPlayerView()
        view.configure(resourceName: resourceName)
        return view
    }

    func updateUIView(_ uiView: AirWriteLetterPlayerView, context: Context) {
        if uiView.currentResource != resourceName {
            uiView.configure(resourceName: resourceName)
        }
        uiView.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ uiView: AirWriteLetterPlayerView, coordinator: ()) {
        uiView.stop()
    }
}

private final class AirWriteLetterPlayerView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    var currentResource: String?

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    func configure(resourceName: String) {
        stop()
        currentResource = resourceName

        guard let url = HowToVideoURL.resolve(named: resourceName) else { return }
        let queuePlayer = AVQueuePlayer()
        let playerLooper = AVPlayerLooper(
            player: queuePlayer,
            templateItem: AVPlayerItem(url: url)
        )
        queuePlayer.isMuted = true
        queuePlayer.defaultRate = 1.5

        playerLayer?.player = queuePlayer
        playerLayer?.videoGravity = .resizeAspect

        player = queuePlayer
        looper = playerLooper
        queuePlayer.play()
    }

    func stop() {
        player?.pause()
        playerLayer?.player = nil
        player = nil
        looper = nil
    }

    func setPlaying(_ isPlaying: Bool) {
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }
}
