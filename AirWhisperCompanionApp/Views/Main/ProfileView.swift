import SwiftUI
import UIKit

/// Profile actions and account details ported from `UserProfileViewController`.
struct ProfileView: View {

    @EnvironmentObject private var dataManager: DataManager
    @EnvironmentObject private var appState: AppState

    @State private var activeAlert: ProfileAlert?
    @State private var isRequestingDeletion = false
    @State private var isDeleteOTPPresented = false

    private var profileName: String {
        dataManager.currentUser?.name ?? "-"
    }

    private var profileEmailTitle: String {
        guard let user = dataManager.currentUser else { return "Email" }
        guard let email = user.email, !email.isEmpty else { return "Contact" }
        return "Email"
    }

    private var profileEmailValue: String {
        guard let user = dataManager.currentUser else { return "Not logged in" }
        guard let email = user.email, !email.isEmpty else { return "Not provided" }
        return email
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ProfileInfoRow(
                    title: profileEmailTitle,
                    value: profileEmailValue,
                    valueColor: Color(red: 0.114, green: 0.631, blue: 0.949, opacity: 1)
                )
                .coachMarkTarget("profile-email")

                ProfileInfoRow(
                    title: "Name",
                    value: profileName,
                    valueColor: Color(uiColor: .systemGray)
                )
                .coachMarkTarget("profile-name")

                Button {
                    activeAlert = .signOutConfirmation
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .frame(width: 176)
                .tint(Color(uiColor: .systemRed))
                .disabled(isRequestingDeletion)
                .coachMarkTarget("profile-sign-out")

                Button {
                    activeAlert = .deleteConfirmation
                } label: {
                    HStack(spacing: 8) {
                        if isRequestingDeletion {
                            ProgressView()
                                .tint(Color(uiColor: .systemRed))
                        }
                        Text(isRequestingDeletion ? "Deleting..." : "Delete Account")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .frame(width: 176)
                .tint(Color(uiColor: .systemRed))
                .disabled(isRequestingDeletion)
                .accessibilityLabel("Delete Account")
                .accessibilityHint("Permanently deletes your AirWhisper account and clears app data.")
                .coachMarkTarget("profile-delete-account")

                Button("Reset to Default") {
                    activeAlert = .resetConfirmation
                }
                .buttonStyle(.plain)
                .frame(width: 176, height: 44)
                .foregroundStyle(Color(uiColor: .systemBlue))
                .coachMarkTarget("profile-reset-defaults")
            }
            .padding(.horizontal, Design.contentMargin)
            .padding(.top, 40)
        }
        .background(Design.groupedBackground.ignoresSafeArea())
        .navigationTitle("User Profile")
        .navigationBarTitleDisplayMode(.inline)
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
