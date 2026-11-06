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
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomNavigationBar
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

    private var bottomNavigationBar: some View {
        HStack(spacing: 6) {
            tabButton(.home, title: "Home", symbol: "house.fill")
            tabButton(.people, title: "My People", symbol: "person.2.fill")
        }
        .padding(6)
        .frame(width: 230, height: 66)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Design.groupedBackground)
    }

    private func tabButton(_ tab: MainTab, title: String, symbol: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color(uiColor: .systemBlue) : Color(uiColor: .secondaryLabel))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color(uiColor: .systemBlue).opacity(0.08))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "\(title), selected" : title)
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
