import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.taskManager) private var taskManager
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<TaskItem> { item in
        item.done == false
    }) private var incompleteTasks: [TaskItem]
    @State private var selectedTab = 0
    @State private var onboardingComplete = false

    private var hasCompletedOnboarding: Bool {
        profiles.first?.onboardingCompleted ?? false
    }

    private var todayIncompleteCount: Int {
        incompleteTasks.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var body: some View {
        if hasCompletedOnboarding || onboardingComplete {
            mainTabView
        } else {
            OnboardingContainerView(onboardingComplete: $onboardingComplete)
        }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            ScheduleView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Schedule")
                }
                .tag(1)
                .badge(todayIncompleteCount)

            CheckInsView()
                .tabItem {
                    Image(systemName: "bell.fill")
                    Text("Check-ins")
                }
                .tag(2)

            PatternsView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Patterns")
                }
                .tag(3)

            ChatView()
                .tabItem {
                    Image(systemName: "sparkle")
                    Text("Assistant")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(5)
        }
        .tint(AppColors.accent)
    }
}
