import SwiftUI

enum CoachMarkCoordinateSpace {
    static let name = "AirWhisperCoachMarkCoordinateSpace"
}

struct CoachMarkFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newer in newer })
    }
}

private struct CoachMarkTargetModifier: ViewModifier {
    let target: String

    func body(content: Content) -> some View {
        content
            .id(target)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: CoachMarkFramesPreferenceKey.self,
                        value: [target: geometry.frame(in: .global)]
                    )
                }
            }
    }
}

extension View {
    func coachMarkTarget(_ target: String) -> some View {
        modifier(CoachMarkTargetModifier(target: target))
    }
}
