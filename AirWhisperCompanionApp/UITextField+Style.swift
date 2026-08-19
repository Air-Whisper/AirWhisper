import UIKit

extension UITextField {
    func applyStandardAuthStyle() {
        self.borderStyle = .none
        self.layer.cornerRadius = 12
        self.layer.borderWidth = 1
        
        // Use a standard light gray color for the border
        if #available(iOS 13.0, *) {
            self.layer.borderColor = UIColor.systemGray4.cgColor
        } else {
            self.layer.borderColor = UIColor.lightGray.cgColor
        }
        
        self.clipsToBounds = true
        
        // Add left padding so text doesn't touch the edge
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: self.frame.height))
        self.leftView = paddingView
        self.leftViewMode = .always
        
        // Add right padding as well
        let rightPaddingView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: self.frame.height))
        self.rightView = rightPaddingView
        self.rightViewMode = .unlessEditing
        
        // Add focus actions
        self.addTarget(self, action: #selector(textFieldDidBeginEditingFocus), for: .editingDidBegin)
        self.addTarget(self, action: #selector(textFieldDidEndEditingFocus), for: .editingDidEnd)
    }
    
    @objc private func textFieldDidBeginEditingFocus() {
        self.layer.borderColor = UIColor.systemBlue.cgColor
        self.layer.borderWidth = 2
    }
    
    @objc private func textFieldDidEndEditingFocus() {
        if #available(iOS 13.0, *) {
            self.layer.borderColor = UIColor.systemGray4.cgColor
        } else {
            self.layer.borderColor = UIColor.lightGray.cgColor
        }
        self.layer.borderWidth = 1
    }
    
    func enablePasswordToggle() {
        self.isSecureTextEntry = true
        
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "eye.slash"), for: .normal)
        button.setImage(UIImage(systemName: "eye"), for: .selected)
        button.tintColor = .secondaryLabel
        
        button.addTarget(self, action: #selector(togglePasswordVisibility(_:)), for: .touchUpInside)
        
        // Wrap in a UIView to add padding
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 40))
        button.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        paddingView.addSubview(button)
        
        self.rightView = paddingView
        self.rightViewMode = .always
    }
    
    @objc private func togglePasswordVisibility(_ sender: UIButton) {
        sender.isSelected.toggle()
        self.isSecureTextEntry = !sender.isSelected
        
        // Preserve cursor position
        if let existingText = self.text {
            // Un-setting and re-setting the text fixes the cursor jumping to the end
            self.text = ""
            self.text = existingText
        }
    }
}
