import SwiftUI

private enum MainTab: Hashable {
    case home
    case people
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var coachMarkManager = SwiftUICoachMarkManager()

    @State private var selectedTab: MainTab = .home
    @State private var homePath: [MainNavigationDestination] = []
    @State private var peoplePath: [MainNavigationDestination] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $homePath) {
                        HomeView()
                            .navigationDestination(for: MainNavigationDestination.self) { destination in
                                destinationView(destination)
                            }
                    }
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(MainTab.home)

                    NavigationStack(path: $peoplePath) {
                        ContactsView()
                            .navigationDestination(for: MainNavigationDestination.self) { destination in
                                destinationView(destination)
                            }
                    }
                    .tabItem {
                        Label("My People", systemImage: "person.2.fill")
                    }
                    .tag(MainTab.people)
                }

                if let activeStep = coachMarkManager.activeStep {
                    CoachMarkTourOverlay(
                        manager: coachMarkManager,
                        targetFrame: coachMarkManager.targetFrames[activeStep.target],
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .zIndex(1)
                }
            }
            .coordinateSpace(name: CoachMarkCoordinateSpace.name)
            .onPreferenceChange(CoachMarkFramesPreferenceKey.self) { frames in
                coachMarkManager.updateTargetFrames(frames)
            }
            .animation(.easeInOut(duration: 0.3), value: coachMarkManager.activeScreenKey)
            .environmentObject(dataManager)
            .environmentObject(appState)
            .environmentObject(coachMarkManager)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: MainNavigationDestination) -> some View {
        switch destination {
        case .manageQuickSpeak:
            ManageQuickSpeakView()
        case .history:
            HistoryView()
        case .profile:
            ProfileView()
        case .airWriteHowTo:
            AirWriteHowToView()
        case .orientWriteHowTo:
            OrientWriteHowToView()
        case .quickPhrasesHowTo:
            QuickPhrasesHowToView()
        case .surfaceTapHowTo:
            SurfaceTapHowToView()
        }
    }
}
