import SwiftUI

struct CompanionSetupRequiredView: View {
    let state: WatchCompanionSetupState
    let retry: () -> Void

    var body: some View {
    
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding()
        
    }

    private var iconName: String {
        switch state {
        case .checking:
            return "applewatch"
        case .iphoneAppMissing:
            return "iphone"
        case .signInRequired:
            return "person.crop.circle"
        case .accountDeleted:
            return "person.crop.circle.badge.xmark"
        case .waitingForInitialSync:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle"
        }
    }

    private var title: String {
        switch state {
        case .checking:
            return "Checking Setup"
        case .iphoneAppMissing:
            return "iPhone App Required"
        case .signInRequired:
            return "Sign In on iPhone"
        case .accountDeleted:
            return "Account Deleted"
        case .waitingForInitialSync:
            return "Companion App"
        case .ready:
            return "Ready"
        }
    }

    private var message: String {
        switch state {
        case .checking:
            return "AirWhisper is checking the paired iPhone connection."
        case .iphoneAppMissing:
            return "Install AirWhisper on the paired iPhone before using the watch app."
        case .signInRequired:
            return "Sign in to AirWhisper on the paired iPhone to use the watch app."
        case .accountDeleted:
            return "Your account was deleted from the companion app."
        case .waitingForInitialSync:
            return "Launch the iPhone app once to sync your account, contacts, phrases, and watch settings."
        case .ready:
            return "AirWhisper is ready."
        }
    }
}
