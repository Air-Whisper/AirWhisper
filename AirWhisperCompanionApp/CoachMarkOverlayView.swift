import UIKit

class CoachMarkOverlayView: UIView {
    // full screen overlay that highlights one UI element at a time with a tooltip explaining what it does.
    // Now loaded from XIB with outlets for UI elements
    
    @IBOutlet weak var dimView: UIView!
    @IBOutlet weak var tooltipContainer: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var stepIndicatorLabel: UILabel!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!
    
    private let spotlightLayer = CAShapeLayer()
    private let tooltipArrow = CAShapeLayer()
    
    private var steps: [CoachStep] = []
    private weak var sourceViewController: UIViewController?
    private var currentStepIndex = 0
    private var onComplete: (() -> Void)?
    
    private let tooltipPadding: CGFloat = 16
    private let spotlightPadding: CGFloat = 8
    private let arrowSize: CGFloat = 10
    
    init(steps: [CoachStep], sourceViewController: UIViewController, onComplete: @escaping () -> Void) {
        super.init(frame: .zero)
        
        self.steps = steps
        self.sourceViewController = sourceViewController
        self.onComplete = onComplete
        
        // Load from XIB
        loadFromXIB()
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadFromXIB()
        setupViews()
    }
    
    private func loadFromXIB() {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: "CoachMarkOverlayView", bundle: bundle)
        guard let view = nib.instantiate(withOwner: self, options: nil).first as? UIView else {
            fatalError("Failed to load CoachMarkOverlayView from XIB")
        }
        
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }
    
    private func setupViews() {
        // Configure dim view
        dimView.layer.mask = spotlightLayer
        
        // Allow programmatic frame layout for tooltip (XIB sets translatesAutoresizingMaskIntoConstraints to NO)
        tooltipContainer.translatesAutoresizingMaskIntoConstraints = true
        
        // Configure tooltip container layers
        tooltipContainer.layer.addSublayer(tooltipArrow)
        
        // Wire button actions programmatically (XIB actions target the inner root view, not File's Owner)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)
    }
    
    func showStep(_ index: Int) {
        guard index < steps.count else {
            dismiss()
            return
        }
        
        currentStepIndex = index
        let step = steps[index]
        
        messageLabel.text = step.message
        stepIndicatorLabel.text = "\(index + 1) of \(steps.count)"
        
        let isLast = (index == steps.count - 1)
        nextButton.setTitle(isLast ? "Got it!" : "Next", for: .normal)
        nextButton.backgroundColor = isLast ? UIColor.systemGreen : UIColor.systemBlue
        
        scrollToTargetIfNeeded(step.targetView) { [weak self] in
            guard let self = self else { return }
            
            let targetRect = step.targetView.convert(step.targetView.bounds, to: self)
            let spotlightRect = targetRect.insetBy(dx: -self.spotlightPadding, dy: -self.spotlightPadding)
            
            self.updateSpotlight(spotlightRect: spotlightRect)
            self.layoutTooltip(spotlightRect: spotlightRect, position: step.position)
            
            if index == 0 {
                self.alpha = 0
                UIView.animate(withDuration: 0.3) {
                    self.alpha = 1
                }
            } else {
                self.tooltipContainer.alpha = 0
                UIView.animate(withDuration: 0.25) {
                    self.tooltipContainer.alpha = 1
                }
            }
        }
    }
    
    private func scrollToTargetIfNeeded(_ targetView: UIView, completion: @escaping () -> Void) {
        guard let scrollView = findParentScrollView(of: targetView) else {
            completion()
            return
        }
        
        let targetFrame = targetView.convert(targetView.bounds, to: scrollView)
        let visibleRect = CGRect(origin: scrollView.contentOffset, size: scrollView.bounds.size)
        
        if visibleRect.contains(targetFrame) {
            completion()
            return
        }
        
        let scrollTarget = CGRect(
            x: targetFrame.origin.x,
            y: max(0, targetFrame.origin.y - 60),
            width: targetFrame.width,
            height: targetFrame.height + 120
        )
        
        UIView.animate(withDuration: 0.3, animations: {
            scrollView.scrollRectToVisible(scrollTarget, animated: false)
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                completion()
            }
        }
    }
    
    private func findParentScrollView(of view: UIView) -> UIScrollView? {
        var current = view.superview
        while let parent = current {
            if let scrollView = parent as? UIScrollView {
                return scrollView
            }
            current = parent.superview
        }
        return nil
    }
    
    private func updateSpotlight(spotlightRect: CGRect) {
        let fullPath = UIBezierPath(rect: bounds)
        let cutoutPath = UIBezierPath(roundedRect: spotlightRect, cornerRadius: 10)
        fullPath.append(cutoutPath)
        fullPath.usesEvenOddFillRule = true
        
        spotlightLayer.path = fullPath.cgPath
        spotlightLayer.fillRule = .evenOdd
        spotlightLayer.fillColor = UIColor.white.cgColor
    }
    
    private func layoutTooltip(spotlightRect: CGRect, position: CoachStep.TooltipPosition) {
        let maxWidth: CGFloat = min(bounds.width - 32, 320)
        let textWidth = maxWidth - (tooltipPadding * 2)
        let messageSize = messageLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        
        let buttonHeight: CGFloat = 36
        let skipHeight: CGFloat = 24
        let stepHeight: CGFloat = 18
        let spacing: CGFloat = 10
        
        let tooltipHeight = tooltipPadding + messageSize.height + spacing + stepHeight + spacing + buttonHeight + spacing + skipHeight + tooltipPadding
        let tooltipWidth = maxWidth
        
        var tooltipX = spotlightRect.midX - tooltipWidth / 2
        tooltipX = max(16, min(tooltipX, bounds.width - tooltipWidth - 16))
        
        var tooltipY: CGFloat
        switch position {
        case .below:
            tooltipY = spotlightRect.maxY + arrowSize + 8
        case .above:
            tooltipY = spotlightRect.minY - tooltipHeight - arrowSize - 8
        }
        
        tooltipY = max(safeAreaInsets.top + 8, min(tooltipY, bounds.height - tooltipHeight - safeAreaInsets.bottom - 8))
        
        tooltipContainer.frame = CGRect(x: tooltipX, y: tooltipY, width: tooltipWidth, height: tooltipHeight)
        
        var yOffset = tooltipPadding
        
        messageLabel.frame = CGRect(x: tooltipPadding, y: yOffset, width: textWidth, height: messageSize.height)
        yOffset += messageSize.height + spacing
        
        stepIndicatorLabel.frame = CGRect(x: tooltipPadding, y: yOffset, width: textWidth, height: stepHeight)
        yOffset += stepHeight + spacing
        
        nextButton.frame = CGRect(x: tooltipPadding, y: yOffset, width: textWidth, height: buttonHeight)
        yOffset += buttonHeight + spacing
        
        skipButton.frame = CGRect(x: tooltipPadding, y: yOffset, width: textWidth, height: skipHeight)
        
        drawArrow(spotlightRect: spotlightRect, position: position)
    }
    
    private func drawArrow(spotlightRect: CGRect, position: CoachStep.TooltipPosition) {
        let arrowPath = UIBezierPath()
        let tooltipFrame = tooltipContainer.frame
        let arrowCenterX = min(max(spotlightRect.midX - tooltipFrame.minX, 20), tooltipFrame.width - 20)
        
        switch position {
        case .below:
            arrowPath.move(to: CGPoint(x: arrowCenterX - arrowSize, y: 0))
            arrowPath.addLine(to: CGPoint(x: arrowCenterX, y: -arrowSize))
            arrowPath.addLine(to: CGPoint(x: arrowCenterX + arrowSize, y: 0))
        case .above:
            let bottom = tooltipFrame.height
            arrowPath.move(to: CGPoint(x: arrowCenterX - arrowSize, y: bottom))
            arrowPath.addLine(to: CGPoint(x: arrowCenterX, y: bottom + arrowSize))
            arrowPath.addLine(to: CGPoint(x: arrowCenterX + arrowSize, y: bottom))
        }
        arrowPath.close()
        
        tooltipArrow.path = arrowPath.cgPath
        tooltipArrow.fillColor = UIColor.systemBackground.cgColor
    }
    
    @objc private func nextTapped() {
        if currentStepIndex < steps.count - 1 {
            showStep(currentStepIndex + 1)
        } else {
            dismiss()
        }
    }
    
    @objc private func skipTapped() {
        dismiss()
    }
    
    private func dismiss() {
        onComplete?()
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
        }
    }
}
