import Combine
import CoreGraphics
import Foundation

final class SwiftUICoachMarkManager: ObservableObject {
    @Published private(set) var activeScreenKey: String?
    @Published private(set) var steps: [CoachMarkStep] = []
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var targetFrames: [String: CGRect] = [:]

    var activeStep: CoachMarkStep? {
        guard steps.indices.contains(currentStepIndex) else { return nil }
        return steps[currentStepIndex]
    }

    func startTourIfNeeded(screenKey: String, steps: [CoachMarkStep]) {
        guard !steps.isEmpty else { return }

        if activeScreenKey == screenKey {
            guard self.steps != steps else { return }

            let currentTarget = activeStep?.target
            let previousIndex = currentStepIndex
            let updatedIndex = currentTarget.flatMap { target in
                steps.firstIndex(where: { $0.target == target })
            } ?? (steps.indices.contains(previousIndex) ? previousIndex : 0)

            self.steps = steps
            currentStepIndex = updatedIndex
            return
        }

        guard activeScreenKey == nil else { return }
        guard !UserDefaults.standard.bool(forKey: "tour_completed_\(screenKey)") else { return }

        self.steps = steps
        currentStepIndex = 0
        activeScreenKey = screenKey
    }

    func updateTargetFrames(_ frames: [String: CGRect]) {
        targetFrames = frames.filter { _, frame in
            !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
        }
    }

    func advance() {
        guard activeScreenKey != nil else { return }
        if currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
        } else {
            finishTour()
        }
    }

    func skip() {
        finishTour()
    }

    func resetAppTour() {
        UserDefaults.standard.removeObject(forKey: "app_tour_completed")
        ["home", "history", "profile", "quickspeak"].forEach {
            UserDefaults.standard.removeObject(forKey: "tour_completed_\($0)")
        }
        finishTour(markCompleted: false)
    }

    private func finishTour(markCompleted: Bool = true) {
        if markCompleted, let activeScreenKey {
            UserDefaults.standard.set(true, forKey: "tour_completed_\(activeScreenKey)")
        }
        activeScreenKey = nil
        steps = []
        currentStepIndex = 0
    }
}
