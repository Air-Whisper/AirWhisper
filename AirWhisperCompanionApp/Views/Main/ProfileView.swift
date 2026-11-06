import SwiftUI
import UIKit

/// Account details and account actions.
struct ProfileView: View {

    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var activeAlert: ProfileAlert?
    @State private var isRequestingDeletion = false
    @State private var isDeleteOTPPresented = false
    @State private var profileName = "-"
    @State private var profileEmailTitle = "Email"
    @State private var profileEmailValue = "Not logged in"

    private let profileBlue = Color(red: 0.08, green: 0.43, blue: 0.91, opacity: 1)
    private let cardColor = Color(uiColor: .secondarySystemGroupedBackground)

    private var profileInitials: String {
        let nameParts = profileName.split(whereSeparator: \.isWhitespace).filter { $0 != "-" }
        guard let first = nameParts.first?.first else { return "AW" }

        var initials = String(first).uppercased()
        if nameParts.count > 1, let last = nameParts.last?.first {
            initials += String(last).uppercased()
        }
        return initials
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                navigationHeader

                identityHeader
                    .padding(.top, 28)

                accountDetailsSection
                    .padding(.top, 24)

                preferencesSection
                    .padding(.top, 24)

                signOutButton
                    .padding(.top, 26)

                deleteAccountButton
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(Design.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .coachMarkTour(
            screenKey: "profile",
            steps: [
                CoachMarkStep(target: "profile-name", message: "Your registered name is shown here.", position: .below),
                CoachMarkStep(target: "profile-email", message: "Your email address.", position: .below),
                CoachMarkStep(target: "profile-sign-out", message: "Tap to sign out and restart the onboarding flow.", position: .above),
                CoachMarkStep(target: "profile-delete-account", message: "Permanently delete your account and app data here.", position: .above),
                CoachMarkStep(target: "profile-reset-defaults", message: "Reset watch settings to factory defaults and clear tap calibration.", position: .above)
            ]
        )
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .signOutConfirmation:
                Alert(
                    title: Text("Sign Out"),
                    message: Text("Are you sure you want to sign out?"),
                    primaryButton: .destructive(Text("Sign Out")) {
                        appState.signOut()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case .deleteConfirmation:
                Alert(
                    title: Text("Delete Account?"),
                    message: Text("This permanently erases your account, contacts, phrases, settings, and history. This cannot be undone."),
                    primaryButton: .destructive(Text("Continue")) {
                        requestDeletionOTP()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case .resetConfirmation:
                Alert(
                    title: Text("Reset to Default?"),
                    message: Text("Your watch sensitivity, voice guidance, tap detector settings, and quick phrases will return to defaults. Tap calibration will be cleared and you will need to redo it."),
                    primaryButton: .destructive(Text("Reset")) {
                        resetToDefaults()
                    },
                    secondaryButton: .cancel(Text("Cancel"))
                )
            case let .message(title, message):
                Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .fullScreenCover(isPresented: $isDeleteOTPPresented) {
            DeleteAccountOTPView(email: dataManager.currentUser?.email ?? "")
                .environmentObject(dataManager)
                .environmentObject(appState)
        }
        .onAppear(perform: loadUserData)
    }

    private var navigationHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(cardColor, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()
        }
        .overlay {
            Text("User Profile")
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .allowsHitTesting(false)
        }
        .frame(height: 48)
    }

    private var identityHeader: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(cardColor)
                .frame(width: 92, height: 92)
                .overlay {
                    Circle()
                        .fill(profileBlue)
                        .frame(width: 84, height: 84)
                        .overlay {
                            Text(profileInitials)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                                .accessibilityLabel("Profile initials \(profileInitials)")
                        }
                }
                .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)

            Text(profileName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)
                .coachMarkTarget("profile-name")
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var accountDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ACCOUNT DETAILS")

            VStack(spacing: 0) {
                ProfileAccountDetailRow(
                    title: "Name",
                    value: profileName,
                    symbol: "person"
                )

                Divider()
                    .padding(.leading, 66)

                ProfileAccountDetailRow(
                    title: profileEmailTitle,
                    value: profileEmailValue,
                    symbol: "envelope"
                )
                .coachMarkTarget("profile-email")
            }
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("PREFERENCES")

            VStack(spacing: 0) {
                Button {
                    activeAlert = .resetConfirmation
                } label: {
                    HStack {
                        Text("Reset to Default")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .coachMarkTarget("profile-reset-defaults")

                Divider()

                Link(destination: URL(string: "https://www.airwhisper.in/how-to-use")!) {
                    HStack {
                        Text("Learn More")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                    .font(.system(size: 17))
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(cardColor, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var signOutButton: some View {
        Button {
            activeAlert = .signOutConfirmation
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(isRequestingDeletion)
        .coachMarkTarget("profile-sign-out")
    }

    private var deleteAccountButton: some View {
        Button {
            activeAlert = .deleteConfirmation
        } label: {
            HStack(spacing: 8) {
                if isRequestingDeletion {
                    ProgressView()
                        .tint(Color(uiColor: .systemRed))
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                }
                Text(isRequestingDeletion ? "Deleting..." : "Delete Account")
                    .font(.system(size: 17))
            }
            .foregroundStyle(Color(uiColor: .systemRed))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRequestingDeletion)
        .accessibilityLabel("Delete Account")
        .accessibilityHint("Permanently deletes your AirWhisper account and clears app data.")
        .coachMarkTarget("profile-delete-account")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color(uiColor: .systemGray2))
            .padding(.leading, 8)
    }

    private func loadUserData() {
        guard let user = dataManager.currentUser else {
            profileEmailTitle = "Email"
            profileEmailValue = "Not logged in"
            profileName = "-"
            return
        }

        profileName = user.name
        if let email = user.email, !email.isEmpty {
            profileEmailTitle = "Email"
            profileEmailValue = email
        } else {
            profileEmailTitle = "Contact"
            profileEmailValue = "Not provided"
        }
    }

    private func requestDeletionOTP() {
        isRequestingDeletion = true
        Task {
            do {
                try await AuthService.requestDeleteOTP()
                await MainActor.run {
                    isRequestingDeletion = false
                    isDeleteOTPPresented = true
                }
            } catch {
                await MainActor.run {
                    isRequestingDeletion = false
                    activeAlert = .message(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func resetToDefaults() {
        dataManager.resetSettingsToDefaults()
        activeAlert = .message(
            title: "Settings Reset",
            message: "Your watch settings and quick phrases are back to defaults. Tap calibration has been cleared — you will need to redo it the next time you enable tap detector."
        )
    }
}

private enum ProfileAlert: Identifiable {
    case signOutConfirmation
    case deleteConfirmation
    case resetConfirmation
    case message(title: String, message: String)

    var id: String {
        switch self {
        case .signOutConfirmation: "sign-out"
        case .deleteConfirmation: "delete"
        case .resetConfirmation: "reset"
        case let .message(title, message): "message-\(title)-\(message)"
        }
    }
}
