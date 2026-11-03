import SwiftUI
import AVFoundation

struct SurfaceTapHowToView: View {
    @State private var isVisible = false

    private let accentColor = Color(red: 0.114, green: 0.631, blue: 0.949, opacity: 1)

    private let steps: [(title: String, detail: String)] = [
        (
            "Turn on Tap Detector in the iPhone app",
            "Open AirWhisper on iPhone → Home screen → Watch Settings → toggle \"Tap Detector\" ON. The setting syncs to the Watch over Bluetooth."
        ),
        (
            "Complete the one-time calibration on the Watch",
            "The first time Tap Detector is enabled, the Watch opens a calibration screen. You'll tap a surface 3 times for single taps, then 3 times with a quick double-tap. The Watch learns your specific tap force and timing from the accelerometer data and saves it."
        ),
        (
            "Rest your wrist on any surface",
            "Place your wrist or hand lightly on a bed, table, chair arm, or any flat surface. No need to move your arm - the vibration from your fingertip travels through your wrist to the Watch."
        ),
        (
            "Single tap → move to the next phrase",
            "One light tap advances through your Quick Phrase list and speaks the highlighted phrase aloud. The Watch highlights each phrase in green so you can follow along visually."
        ),
        (
            "Double tap → select and send the phrase",
            "Two quick taps in succession confirm the currently highlighted phrase. It opens the send screen so the phrase can be sent as a message."
        ),
        (
            "Tap Detector works only in Quick Speak",
            "Surface Tap is active exclusively on the Quick Speak screen. Air Write and Orient Write continue to work via their own controls when the standard mode is active."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ZStack {
                    Color.white
                    LoopingVideoView(
                        resourceName: "HowToUse4Video",
                        videoGravity: .resizeAspect,
                        isPlaying: isVisible
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 16) {
                    Text("What is Surface Tap?")
                        .font(.system(size: 20, weight: .bold))

                    Text("Some patients were unable to consistently perform gestures like pinch and clench. Surface Tap lets them communicate by tapping any nearby surface - a bed rail, table, or their own leg. The Apple Watch detects the vibration and helps them navigate through Quick Phrases hands-free.")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("How to Set Up")
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
                            if index < steps.count - 1 {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(accentColor.opacity(0.25))
                                        .frame(width: 2, height: max(0, geometry.size.height - 32))
                                        .offset(x: 15, y: 32)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.groupedBackground)
        .navigationTitle("Surface Tap - How to Use")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
