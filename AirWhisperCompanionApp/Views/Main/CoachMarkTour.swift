import SwiftUI

private struct CoachMarkTourModifier: ViewModifier {
    @EnvironmentObject private var manager: SwiftUICoachMarkManager

    let screenKey: String
    let steps: [CoachMarkStep]

    func body(content: Content) -> some View {
        ScrollViewReader { scrollProxy in
            content
                .onAppear {
                    manager.startTourIfNeeded(screenKey: screenKey, steps: steps)
                    scrollToCurrentTarget(using: scrollProxy)
                }
                .onChange(of: steps) { _, updatedSteps in
                    manager.startTourIfNeeded(screenKey: screenKey, steps: updatedSteps)
                    scrollToCurrentTarget(using: scrollProxy)
                }
                .onChange(of: manager.activeScreenKey) { _, _ in
                    scrollToCurrentTarget(using: scrollProxy)
                }
                .onChange(of: manager.currentStepIndex) { _, _ in
                    scrollToCurrentTarget(using: scrollProxy)
                }
        }
    }

    private func scrollToCurrentTarget(using proxy: ScrollViewProxy) {
        guard manager.activeScreenKey == screenKey,
              let step = manager.activeStep else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(step.target, anchor: .center)
        }
    }
}

extension View {
    func coachMarkTour(screenKey: String, steps: [CoachMarkStep]) -> some View {
        modifier(CoachMarkTourModifier(screenKey: screenKey, steps: steps))
    }
}
