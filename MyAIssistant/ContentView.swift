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
                    HomeView(selectedTab: $selectedTab)
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
            // Cold-launch path for StartFocusIntent: NotificationCenter posts
            // before any observer exists, so the intent persists a request to
            // UserDefaults and we replay it here. 30s freshness window prevents
            // firing a stale request from a previous session.
            consumePendingFocusRequest()
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

    /// Replay a StartFocusIntent request that arrived via cold launch. The
    /// intent's NotificationCenter post runs before ContentView's observer is
    /// registered, so we persist the request and consume it here. 30s
    /// freshness prevents a request left over from a terminated previous
    /// session from auto-opening the focus timer.
    private func consumePendingFocusRequest() {
        let defaults = UserDefaults.standard
        let requestedAt = defaults.double(forKey: "pendingFocusRequestedAt")
        guard requestedAt > 0 else { return }
        let duration = defaults.integer(forKey: "pendingFocusDurationMinutes")
        defaults.removeObject(forKey: "pendingFocusRequestedAt")
        defaults.removeObject(forKey: "pendingFocusDurationMinutes")
        let age = Date().timeIntervalSince1970 - requestedAt
        guard age < 30 else { return }
        focusDuration = duration > 0 ? duration : 25
        showingFocusTimer = true
    }

    private func navigateToDestination(_ destination: String) {
        switch destination {
        case "assistant", "chat":
            showingChat = true
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
