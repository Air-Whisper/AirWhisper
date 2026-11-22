import SwiftUI
import AVFoundation

struct QuickPhrasesHowToView: View {
    @State private var isVisible = false

    private let accentColor = Color(red: 0.114, green: 0.631, blue: 0.949, opacity: 1)

    private let steps: [(title: String, detail: String)] = [
        (
            "Open the AirWhisper companion app",
            "Launch AirWhisper on your iPhone and go to the Home screen."
        ),
        (
            "Tap \"Manage Quick Phrases\"",
            "Type a phrase in the text field and tap Add. The phrase appears in the list immediately."
        ),
        (
            "Use phrases that matter most",
            "Add up to 10 phrases. If the list is full, the least-used phrase is automatically replaced — you'll see an alert when this happens."
        ),
        (
            "Phrases sync to your Watch automatically",
            "Once added, phrases are sent to your Apple Watch over Bluetooth and backed up to iCloud — so they're there even after pairing a new Watch."
        ),
        (
            "On the Watch, open Quick Speak",
            "Tap any phrase in the list to have the Watch speak it instantly. The most recently used phrase moves to the top for faster access next time."
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ZStack {
                    Color.white
                    LoopingVideoView(
                        resourceName: "HowToUse3Video",
                        videoGravity: .resizeAspect,
                        isPlaying: isVisible
                    )
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 16) {
                    Text("What are Quick Phrases?")
                        .font(.system(size: 20, weight: .bold))

                    Text("Quick Phrases are pre-saved sentences that the Apple Watch reads aloud the moment you tap them. \"HELP\" is always pinned at the top.")
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

                    NavigationLink(value: MainNavigationDestination.manageQuickSpeak) {
                        Text("Manage Quick Phrases →")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.groupedBackground)
        .navigationTitle("Quick Phrases - How to Use")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
