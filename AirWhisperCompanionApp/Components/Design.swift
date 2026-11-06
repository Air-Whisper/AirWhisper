import SwiftUI
import UIKit

/// Shared design constants — brand colors and control styling taken verbatim
/// from the UIKit storyboard values (see Main.storyboard rgb values).
enum Design {

    /// Primary brand color used by all primary buttons and the OTP accent.
    /// Storyboard value: RGB(10, 96, 198) = (0.039, 0.376, 0.776).
    static let brandBlue = Color(red: 0.039, green: 0.376, blue: 0.776, opacity: 1)

    /// Destructive red used by the account-deletion OTP screen.
    /// Storyboard value: RGB(255, 56, 60).
    static let destructiveRed = Color(red: 1, green: 0.2196, blue: 0.2353, opacity: 1)

    /// Neutral button background used by the Google button (storyboard 0.949 gray).
    static let neutralButton = Color(white: 0.949)

    /// Secondary label color used throughout the storyboard.
    static let secondaryLabel = Color(uiColor: .secondaryLabel)

    /// System link color (legal agreement links).
    static let link = Color(uiColor: .link)

    /// Default content margins used across screens (storyboard: 20–24pt insets).
    static let contentMargin: CGFloat = 20

    /// Standard screen background.
    static let background = Color(uiColor: .systemBackground)

    /// Grouped background used by the How-To screens.
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
}
