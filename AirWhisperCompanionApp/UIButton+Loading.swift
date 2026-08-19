import UIKit

extension UIButton {
    func showLoading() {
        if viewWithTag(9999) != nil { return }
        self.isUserInteractionEnabled = false
        
        let overlay = UIView()
        overlay.backgroundColor = self.backgroundColor
        overlay.layer.cornerRadius = self.layer.cornerRadius
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isUserInteractionEnabled = false
        overlay.tag = 9998
        self.addSubview(overlay)
        
        let indicator = UIActivityIndicatorView(style: .medium)
        let isLight = backgroundColor?.isLight ?? false
        indicator.color = isLight ? .darkGray : .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.tag = 9999
        overlay.addSubview(indicator)
        
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: self.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            
            indicator.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])
        
        indicator.startAnimating()
    }
    
    func hideLoading() {
        self.isUserInteractionEnabled = true
        if let overlay = self.viewWithTag(9998) {
            overlay.removeFromSuperview()
        }
    }
}

extension UIColor {
    var isLight: Bool {
        guard let components = cgColor.components else { return false }
        let red = components[0]
        let green = components.count > 1 ? components[1] : components[0]
        let blue = components.count > 2 ? components[2] : components[0]
        let brightness = ((red * 299) + (green * 587) + (blue * 114)) / 1000
        return brightness > 0.5
    }
}
