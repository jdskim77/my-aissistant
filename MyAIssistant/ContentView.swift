import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.networkMonitor) private var networkMonitor
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<TaskItem> { item in
        item.done == false
    }) private var incompleteTasks: [TaskItem]
    @State private var selectedTab: Tab = .home
    @State private var onboardingComplete = false
    @State private var showingChat = false
    @State private var showingFocusTimer = false
    @State private var focusDuration = 25

    private var hasCompletedOnboarding: Bool {
        profiles.first?.onboardingCompleted ?? false
    }

    private var todayIncompleteCount: Int {
        incompleteTasks.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding || onboardingComplete {
                mainView
            } else {
                OnboardingContainerView(onboardingComplete: $onboardingComplete)
            }
        }
        .offlineBanner()
    }

    private var mainView: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .schedule:
                    ScheduleView()
                case .compass:
                    CompassTabView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 56)

            CustomTabBar(
                selectedTab: $selectedTab,
                onAITap: { showingChat = true },
                scheduleBadge: todayIncompleteCount
            )
        }
        .tint(AppColors.accent)
        .fullScreenCover(isPresented: $showingChat) {
            ChatView(onDismiss: { showingChat = false })
        }
        .sheet(isPresented: $showingFocusTimer) {
            FocusTimerView(workMinutes: focusDuration)
        }
        .onReceive(NotificationCenter.default.publisher(for: .startFocusSession)) { notification in
            if let duration = notification.userInfo?["duration"] as? Int {
                focusDuration = duration
            }
            showingFocusTimer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .didTapNotification)) { notification in
            guard let destination = notification.userInfo?["destination"] as? String else { return }
            navigateToDestination(destination)
        }
        .onAppear {
            // Handle cold-launch: app was opened by tapping a notification while not running
            if let pending = NotificationDelegate.shared.pendingDestination {
                NotificationDelegate.shared.pendingDestination = nil
                navigateToDestination(pending)
            }
        }
        .task {
            // Delayed check for cold-launch race: didReceive is async and may complete
            // after onAppear fires. Re-check after a brief delay.
            try? await Task.sleep(for: .milliseconds(500))
            if let pending = NotificationDelegate.shared.pendingDestination {
                NotificationDelegate.shared.pendingDestination = nil
                navigateToDestination(pending)
            }
        }
    }

    private func navigateToDestination(_ destination: String) {
        switch destination {
        case "schedule":
            selectedTab = .schedule
        case "compass", "patterns":
            selectedTab = .compass
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .home
        }
    }
}
