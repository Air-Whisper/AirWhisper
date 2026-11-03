import SwiftUI
import AVFoundation

struct OrientWriteHowToView: View {
    @State private var isVisible = false

    private let accentColor = Color(red: 0.114, green: 0.631, blue: 0.949, opacity: 1)

    private let steps: [(title: String, detail: String)] = [
        (
            "Open OrientWrite on Your Watch",
            "From the writing modes, tap OrientWrite. A virtual writing canvas will appear, and the watch will begin tracking your wrist movements."
        ),
        (
            "Keep Your Wrist Steady Before Writing",
            "A small cursor indicates the current writing position. Hold your wrist still for a moment to allow the cursor to stabilize before you begin writing."
        ),
        (
            "Move the Cursor Using Wrist Tilts",
            "Tilt your wrist left or right (roll) to move the cursor horizontally. Tilt it up or down (pitch) to move the cursor vertically. Small unintentional movements are filtered out to help keep the cursor steady and improve writing accuracy."
        ),
        (
            "Tap Start and Write a Letter",
            "Tap the Start button to begin recording your input. Use wrist tilts to guide the cursor and trace a letter on the virtual canvas. OrientWrite tracks the cursor's path as you write. When you finish, tap Stop. The cursor turns green to confirm that the stroke has been successfully recorded."
        ),
        (
            "Wait for Letter Recognition",
            "Once recording stops, the captured stroke data is processed by the handwriting recognition system. The system analyzes the shape drawn on the canvas, identifies the corresponding letter, and adds it to your message. The recognized letter is also spoken aloud for confirmation. If recognition is unsuccessful, try again."
        ),
        (
            "Correct Mistakes Using the Backspace Button",
            "If an incorrect letter is recognized or added by mistake, tap the Backspace (←) button to remove the most recently entered character. This allows you to make corrections without restarting your message."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ZStack {
                    Color.white
                    LoopingVideoView(
                        resourceName: "HowToUse2Video",
                        videoGravity: .resizeAspectFill,
                        isPlaying: isVisible
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 8) {
                    Text("How It Works")
                        .font(.system(size: 20, weight: .bold))

                    Text("OrientWrite allows you to compose messages using wrist movements, including roll (left/right tilt) and pitch (up/down tilt). These wrist motions control the cursor on a virtual canvas, enabling you to draw letters directly on the watch face. As you move your wrist, the cursor follows your gestures, allowing you to write messages intuitively without touching the screen.")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("How to Use")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 8) {
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
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.groupedBackground)
        .navigationTitle("OrientWrite - How to Use")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
