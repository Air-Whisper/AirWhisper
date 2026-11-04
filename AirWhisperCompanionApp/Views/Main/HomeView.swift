import SwiftUI
import AVFoundation
import UIKit

struct HomeView: View {
    @EnvironmentObject private var dataManager: DataManager

    @State private var sensitivity = Double(WatchSettings.defaultValue)
    @State private var voiceGuidance = false
    @State private var tapDetectorEnabled = false
    @State private var isHowToExpanded = false
    @State private var isHomeVisible = false
    @State private var carouselPage = 0
    @State private var isLoadingSettings = false
    @State private var settingsSyncTask: Task<Void, Never>?

    private let settingsSyncDebounceInterval: TimeInterval = 0.3

    private let accentColor = Color(
        red: 0.1137254902,
        green: 0.631372549,
        blue: 0.9490196078,
        opacity: 1
    )

    private let tutorialEntries: [HomeTutorialEntry] = [
        HomeTutorialEntry(
            pageIndex: 0,
            title: "AirWrite",
            description: "Draw letters in the air using your wrist. The watch recognizes motion and converts it to text.",
            resourceName: "HowToUse1Video",
            destination: .airWriteHowTo,
            usesAspectFill: false
        ),
        HomeTutorialEntry(
            pageIndex: 1,
            title: "OrientWrite",
            description: "Tilt and rotate your wrist to select characters from a virtual keyboard on the watch face.",
            resourceName: "HowToUse2Video",
            destination: .orientWriteHowTo,
            usesAspectFill: true
        ),
        HomeTutorialEntry(
            pageIndex: 2,
            title: "Quick Phrases",
            description: "Tap a saved phrase to instantly send it  no typing needed.",
            resourceName: "HowToUse3Video",
            destination: .quickPhrasesHowTo,
            usesAspectFill: false
        ),
        HomeTutorialEntry(
            pageIndex: 3,
            title: "Surface Tap",
            description: "Use single or double surface taps on nearby objects to move through phrases without touching the watch.",
            resourceName: "HowToUse4Video",
            destination: .surfaceTapHowTo,
            usesAspectFill: false
        )
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                howToSection
                quickSpeakSection
                watchSettingsSection
                historySection
            }
            .padding(.horizontal, Design.contentMargin)
            .padding(.top, 15)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Design.groupedBackground)
        .coachMarkTour(
            screenKey: "home",
            steps: [
                CoachMarkStep(
                    target: "home-how-to",
                    message: "Tap to expand or collapse the How to Use tips.",
                    position: .below
                ),
                CoachMarkStep(
                    target: "home-sensitivity",
                    message: "Drag to adjust watch cursor sensitivity. Higher = more responsive.",
                    position: .above
                ),
                CoachMarkStep(
                    target: "home-voice-guidance",
                    message: "Toggle to enable/disable spoken feedback on your Apple Watch.",
                    position: .above
                ),
                CoachMarkStep(
                    target: "home-tap-detector",
                    message: "Enable to use surface-tap gestures instead of touch on Apple Watch.",
                    position: .above
                )
            ]
        )
        .onAppear {
            loadWatchSettings()
            isHomeVisible = true
        }
        .onDisappear {
            isHomeVisible = false
            flushPendingSettingsSync()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("AirWhisperLogoLightmode")
                .resizable()
                .scaledToFit()
                .frame(width: 278, height: 54, alignment: .leading)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            NavigationLink(value: MainNavigationDestination.profile) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(accentColor)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .frame(height: 70)
    }

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tutorial")
                .font(.system(size: 20, weight: .bold))

            VStack(spacing: 0) {
                Button(action: toggleHowTo) {
                    HStack {
                        Text("How to Use")
                            .font(.system(size: 17))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: isHowToExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .coachMarkTarget("home-how-to")

                TabView(selection: $carouselPage) {
                    ForEach(tutorialEntries) { entry in
                        NavigationLink(value: entry.destination) {
                            HomeTutorialCard(
                                entry: entry,
                                isPlaying: isHowToExpanded && isHomeVisible
                            )
                        }
                        .buttonStyle(.plain)
                        .tag(entry.pageIndex)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .tint(accentColor)
                .frame(height: isHowToExpanded ? 330 : 0)
                .clipped()
                .opacity(isHowToExpanded ? 1 : 0)
                .accessibilityHidden(!isHowToExpanded)
            }
            .background(Design.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var quickSpeakSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Speak Phrases")
                .font(.system(size: 20, weight: .bold))

            Text("Input and save commonly used words, phrases, or sentences for instant access with gestures.")
                .font(.system(size: 13))
                .foregroundStyle(Design.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: MainNavigationDestination.manageQuickSpeak) {
                HStack {
                    Text("Add new phrase")
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 15)
                .padding(.trailing, 12)
                .frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Design.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var watchSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Watch Settings")
                .font(.system(size: 20, weight: .bold))
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                Text("Sensitivity")
                    .font(.system(size: 17))

                Slider(value: $sensitivity, in: Double(WatchSettings.minValue)...Double(WatchSettings.maxValue))
                    .tint(accentColor)
                    .padding(.top, 8)
                    .accessibilityLabel("Watch cursor sensitivity")
                    .accessibilityHint("Adjusts how responsive the Apple Watch cursor is.")
                    .accessibilityValue("\(Int(sensitivity.rounded())) percent")
                    .coachMarkTarget("home-sensitivity")
                    .onChange(of: sensitivity) { _, _ in
                        settingsControlChanged()
                    }

                HStack {
                    Text("Low")
                    Spacer()
                    Text("High")
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .padding(.top, 5)

                SettingsToggleRow(
                    title: "Voice Guidance",
                    description: "Speaks element names via Watch speaker when navigating using AssistiveTouch (pinch/clench) and reads recognized letters aloud.",
                    isOn: $voiceGuidance,
                    accessibilityLabel: "Voice guidance",
                    accessibilityHint: "Toggles spoken feedback on the Apple Watch.",
                    target: "home-voice-guidance"
                )
                .padding(.top, 20)
                .onChange(of: voiceGuidance) { _, _ in
                    settingsControlChanged()
                }

                SettingsToggleRow(
                    title: "Tap Detector",
                    description: "Patient Accessibility: Use Single/Double Surface Taps on physical objects (like beds) to navigate phrases on the watch.",
                    isOn: $tapDetectorEnabled,
                    accessibilityLabel: "Tap detector",
                    accessibilityHint: "Toggles surface-tap gesture detection on the Apple Watch.",
                    target: "home-tap-detector"
                )
                .padding(.top, 20)
                .onChange(of: tapDetectorEnabled) { _, _ in
                    settingsControlChanged()
                }

                NavigationLink(value: MainNavigationDestination.profile) {
                    (Text("Recalibrate")
                        .foregroundColor(Color(uiColor: .systemBlue))
                        .underline()
                     + Text(" tap detection from your profile")
                        .foregroundColor(Color(uiColor: .systemGray)))
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(16)
            .background(Design.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.system(size: 20, weight: .bold))

            NavigationLink(value: MainNavigationDestination.history) {
                HStack {
                    Text("Message History")
                        .font(.system(size: 17))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 15)
                .padding(.trailing, 12)
                .frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Design.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func loadWatchSettings() {
        isLoadingSettings = true
        if let settings = dataManager.getWatchSettings() {
            sensitivity = Double(settings.sensitivity)
            voiceGuidance = settings.voiceGuidance
            tapDetectorEnabled = settings.tapDetectorEnabled
        } else {
            sensitivity = Double(WatchSettings.defaultValue)
            voiceGuidance = false
            tapDetectorEnabled = false
        }
        Task { @MainActor in
            await Task.yield()
            isLoadingSettings = false
        }
    }

    private func settingsControlChanged() {
        guard !isLoadingSettings else { return }
        scheduleDebouncedSettingsSync()
    }

    private func toggleHowTo() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isHowToExpanded.toggle()
        }
    }

    private func scheduleDebouncedSettingsSync() {
        settingsSyncTask?.cancel()

        let capturedSensitivity = Float(sensitivity)
        let capturedVoiceGuidance = voiceGuidance
        let capturedTapDetectorEnabled = tapDetectorEnabled
        let manager = dataManager
        settingsSyncTask = Task {
            do {
                try await Task.sleep(for: .seconds(settingsSyncDebounceInterval))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            manager.updateSensitivity(capturedSensitivity)
            manager.updateVoiceGuidance(capturedVoiceGuidance)
            manager.updateTapDetectorEnabled(capturedTapDetectorEnabled)
        }
    }

    private func flushPendingSettingsSync() {
        guard let pending = settingsSyncTask else { return }
        pending.cancel()
        settingsSyncTask = nil

        dataManager.updateSensitivity(Float(sensitivity))
        dataManager.updateVoiceGuidance(voiceGuidance)
        dataManager.updateTapDetectorEnabled(tapDetectorEnabled)
    }

}

private struct HomeTutorialEntry: Identifiable {
    let pageIndex: Int
    let title: String
    let description: String
    let resourceName: String
    let destination: MainNavigationDestination
    let usesAspectFill: Bool

    var id: String { resourceName }
}

private struct HomeTutorialCard: View {
    let entry: HomeTutorialEntry
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LoopingVideoView(
                resourceName: entry.resourceName,
                videoGravity: entry.usesAspectFill ? .resizeAspectFill : .resizeAspect,
                isPlaying: isPlaying
            )
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .clipped()

            Text(entry.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Text(entry.description)
                .font(.system(size: 13))
                .foregroundStyle(Design.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let target: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17))

                Spacer(minLength: 0)

                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .tint(Color(uiColor: .systemGreen))
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(accessibilityHint)
                    .accessibilityValue(isOn ? "On" : "Off")
                    .coachMarkTarget(target)
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(Design.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
