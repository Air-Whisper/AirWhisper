import SwiftUI
import UIKit
import AVFoundation

/// Four-page onboarding carousel:
/// - 4 pages from `OnboardingItem.items`
/// - swipe left/right to move between pages (guarded while transitioning)
/// - page indicator + Skip button (title becomes "Next" on the last page)
/// - per-page looping video with the original spring entrance / exit animations
struct OnboardingView: View {

    @EnvironmentObject private var appState: AppState

    @State private var currentPage: Int = 0
    @State private var isTransitioning = false

    // Entrance animation state (ported from the view controller's transforms)
    @State private var mediaAlpha: CGFloat = 0
    @State private var mediaOffsetY: CGFloat = 0
    @State private var titleAlpha: CGFloat = 0
    @State private var titleOffsetY: CGFloat = 18
    @State private var descriptionAlpha: CGFloat = 0
    @State private var descriptionOffsetY: CGFloat = 14

    private let onboardingScreens = OnboardingItem.items

    private var currentItem: OnboardingItem {
        onboardingScreens[min(currentPage, onboardingScreens.count - 1)]
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let arcHeight = min(362, size.height * 0.48)
            let videoTop: CGFloat = 90
            let videoHeight = max(0, size.height - videoTop - arcHeight + 55)

            ZStack(alignment: .bottom) {
                Design.background

                // Keep the video behind the arc so the blue shape masks its lower edge.
                LoopingVideoView(
                    resourceName: currentItem.video,
                    videoGravity: currentItem.video == "HowToUse2Video" ? .resizeAspectFill : .resizeAspect
                )
                .frame(width: size.width, height: videoHeight)
                .position(x: size.width / 2, y: videoTop + videoHeight / 2)
                .opacity(mediaAlpha)
                .offset(y: mediaOffsetY)
                .zIndex(0)

                // The original arc is a full-width, 362pt image pinned to the bottom.
                Image("arc")
                    .resizable()
                    .frame(width: size.width, height: arcHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipped()
                    .ignoresSafeArea(edges: .bottom)
                    .zIndex(1)

                VStack(alignment: .leading, spacing: 20) {
                    Text(currentItem.title)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(y: titleOffsetY)
                        .opacity(titleAlpha)

                    Text(currentItem.description)
                        .font(.body)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 5)
                        .offset(y: descriptionOffsetY)
                        .opacity(descriptionAlpha)
                }
                .frame(width: max(0, size.width - 65), alignment: .leading)
                .padding(.leading, 30)
                .padding(.bottom, 148)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .zIndex(2)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image("AirWhisperLogoLightmode")
                            .resizable()
                            .scaledToFit()
                            .frame(width: min(278, size.width - 120), height: 54, alignment: .leading)
                            .accessibilityHidden(true)

                        Spacer(minLength: 0)

                        Button(action: skipOnboarding) {
                            Text(skipButtonTitle)
                                .font(.system(size: 17))
                                .foregroundStyle(Color(uiColor: .systemBlue))
                                .frame(width: 64, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 24)
                    .padding(.top, 20)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(3)

                PageIndicatorView(numberOfPages: onboardingScreens.count, currentPage: currentPage)
                    .frame(height: 26)
                    .padding(.bottom, 20)
                    .zIndex(3)
            }
        }
        .background(Design.background.ignoresSafeArea())
        .onAppear { animateEntrance() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < 0 {
                        goToNextPage()
                    } else if value.translation.width > 0 {
                        goToPreviousPage()
                    }
                }
        )
    }

    private var skipButtonTitle: String {
        currentPage == onboardingScreens.count - 1 ? "Next" : "Skip"
    }

    private func skipOnboarding() {
        appState.route = .auth
    }

    // MARK: - Paging (ported from goToNextPage / goToPreviousPage)

    private func goToNextPage() {
        guard !isTransitioning else { return }
        guard currentPage < onboardingScreens.count - 1 else { return }
        currentPage += 1
        transitionContent()
    }

    private func goToPreviousPage() {
        guard !isTransitioning else { return }
        guard currentPage > 0 else { return }
        currentPage -= 1
        transitionContent()
    }

    // MARK: - Transitions (ported from transitionContent / animateEntrance)

    private func videoVerticalOffsetY(for resourceName: String) -> CGFloat {
        resourceName == "HowToUse3Video" || resourceName == "HowToUse4Video" ? -18 : 0
    }

    private func prepareForEntranceAnimation() {
        let baseY = videoVerticalOffsetY(for: onboardingScreens[currentPage].video)
        mediaAlpha = 0
        mediaOffsetY = baseY + 18
        titleAlpha = 0
        titleOffsetY = 18
        descriptionAlpha = 0
        descriptionOffsetY = 14
    }

    private func animateEntrance() {
        let baseY = videoVerticalOffsetY(for: onboardingScreens[currentPage].video)

        // Original: UIView.animate(withDuration: 0.8, usingSpringWithDamping: 0.78,
        // initialSpringVelocity: 0.2)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.78, blendDuration: 0)) {
            mediaAlpha = 1
            mediaOffsetY = baseY
        }
        // Title: 0.5s, delay 0.2, curveEaseOut
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            titleAlpha = 1
            titleOffsetY = 0
        }
        // Description: 0.5s, delay 0.4, curveEaseOut
        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            descriptionAlpha = 1
            descriptionOffsetY = 0
        }
    }

    private func transitionContent() {
        guard !isTransitioning else { return }
        isTransitioning = true

        // Fade content out (0.3s, curveEaseInOut)
        withAnimation(.easeInOut(duration: 0.3)) {
            mediaAlpha = 0
            titleAlpha = 0
            descriptionAlpha = 0
        }

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                prepareForEntranceAnimation()
                animateEntrance()
            }
            isTransitioning = false
        }
    }
}

/// UIPageControl wrapper so the onboarding indicator matches the storyboard.
struct PageIndicatorView: UIViewRepresentable {

    let numberOfPages: Int
    let currentPage: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = numberOfPages
        control.currentPage = currentPage
        control.currentPageIndicatorTintColor = UIColor(red: 0.039, green: 0.376, blue: 0.776, alpha: 1)
        control.pageIndicatorTintColor = UIColor.systemGray4
        control.isUserInteractionEnabled = false
        return control
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.numberOfPages = numberOfPages
        uiView.currentPage = currentPage
    }
}
