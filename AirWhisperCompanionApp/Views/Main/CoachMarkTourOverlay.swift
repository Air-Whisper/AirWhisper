import SwiftUI

struct CoachMarkTourOverlay: View {
    @ObservedObject var manager: SwiftUICoachMarkManager

    let targetFrame: CGRect?
    let safeAreaInsets: EdgeInsets

    private let spotlightPadding: CGFloat = 8
    private let tooltipWidthLimit: CGFloat = 320
    private let tooltipHeight: CGFloat = 194
    private let arrowSize: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let target = targetFrame ?? .zero
            let spotlight = target.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
            let width = min(geometry.size.width - 32, tooltipWidthLimit)
            let x = min(max(target.midX, 16 + width / 2), geometry.size.width - 16 - width / 2)
            let requestedY = tooltipCenterY(for: spotlight)
            let minY = safeAreaInsets.top + tooltipHeight / 2 + 8
            let maxY = geometry.size.height - safeAreaInsets.bottom - tooltipHeight / 2 - 8
            let y = min(max(requestedY, minY), maxY)

            ZStack(alignment: .topLeading) {
                CoachMarkSpotlight(cutoutRect: targetFrame == nil ? .zero : spotlight)
                    .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }

                if let step = manager.activeStep {
                    tooltip(step: step, width: width, arrowOffset: target.midX - x)
                        .id(step.id)
                        .transition(.opacity)
                        .position(x: x, y: y)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    private func tooltipCenterY(for spotlight: CGRect) -> CGFloat {
        guard let step = manager.activeStep else { return 0 }
        switch step.position {
        case .below:
            return spotlight.maxY + arrowSize + 8 + tooltipHeight / 2
        case .above:
            return spotlight.minY - arrowSize - 8 - tooltipHeight / 2
        }
    }

    private func tooltip(step: CoachMarkStep, width: CGFloat, arrowOffset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(step.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(manager.currentStepIndex + 1) of \(manager.steps.count)")
                .font(.system(size: 12))
                .foregroundStyle(Design.secondaryLabel.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(manager.currentStepIndex == manager.steps.count - 1 ? "Got it!" : "Next", action: advance)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(manager.currentStepIndex == manager.steps.count - 1 ? Color.green : Color(uiColor: .systemBlue))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Skip Tour", action: skip)
            .font(.system(size: 14))
            .foregroundStyle(Design.secondaryLabel.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 24)
        }
        .padding(16)
        .frame(width: width, height: tooltipHeight)
        .background(Design.background)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: step.position == .below ? .top : .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Design.background)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(45))
                .offset(x: min(max(arrowOffset, -width / 2 + 24), width / 2 - 24), y: step.position == .below ? -7 : 7)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            manager.advance()
        }
    }

    private func skip() {
        withAnimation(.easeInOut(duration: 0.25)) {
            manager.skip()
        }
    }
}

private struct CoachMarkSpotlight: Shape {
    let cutoutRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRoundedRect(in: cutoutRect, cornerSize: CGSize(width: 10, height: 10))
        return path
    }
}
