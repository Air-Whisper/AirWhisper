import UIKit

// holds the data for one step in the guided tour, pointing to a view and what to say about it.
struct CoachStep
{
    let targetView: UIView
    let message: String
    let position: TooltipPosition
    
    enum TooltipPosition
    {
        case above
        case below
    }
}

class CoachMarkManager // manages the one-time onboarding tour shown only once when the app is first installed.
{
    static let shared = CoachMarkManager()
    
    private let appTourSeenKey = "app_tour_completed"
    
    // all per-screen keys used by the app, for rSeset purposes.
    private let allScreenKeys = ["home", "history", "profile", "quickspeak"]
    
    private init() {}
    
    private func tourKey(for screen: String) -> String {
        return "tour_completed_\(screen)"
    }
    
    func hasCompletedAppTour() -> Bool
    {
        return UserDefaults.standard.bool(forKey: appTourSeenKey)
    }
    
    func hasCompletedTour(for screenKey: String) -> Bool
    {
        return UserDefaults.standard.bool(forKey: tourKey(for: screenKey))
    }
    
    func markAppTourCompleted()
    {
        UserDefaults.standard.set(true, forKey: appTourSeenKey)
    }
    
    private func markTourCompleted(for screenKey: String)
    {
        UserDefaults.standard.set(true, forKey: tourKey(for: screenKey))
    }
    
    func resetAppTour()
    {
        UserDefaults.standard.removeObject(forKey: appTourSeenKey)
        for key in allScreenKeys
        {
            UserDefaults.standard.removeObject(forKey: tourKey(for: key))
        }
    }
    // clears all tour flags so every tour shows again (for development/testing purposes).
    
    func showTour(on viewController: UIViewController, steps: [CoachStep], screenKey: String) {
        guard !steps.isEmpty else { return }
        
        let overlay = CoachMarkOverlayView(steps: steps, sourceViewController: viewController) { [weak self] in
            self?.markTourCompleted(for: screenKey)
        }
        
        if let window = viewController.view.window {
            overlay.frame = window.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(overlay)
        } else {
            overlay.frame = viewController.view.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            viewController.view.addSubview(overlay)
        }
        // adds the overlay to the window so it sits above everything including the navigation bar.
        
        overlay.showStep(0)
    }
    
    func showTourIfNeeded(on viewController: UIViewController, steps: [CoachStep], screenKey: String) {
        guard !hasCompletedTour(for: screenKey) else { return }
        showTour(on: viewController, steps: steps, screenKey: screenKey)
    }
    // only shows the tour if the user hasnt completed it yet for this specific screen.
}
