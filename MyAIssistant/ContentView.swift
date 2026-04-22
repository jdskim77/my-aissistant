import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.networkMonitor) private var networkMonitor
    @Query private var profiles: [UserProfile]
    /// Persisted tab selection so returning users land where they left
    /// off across relaunches. Default `.coach` only on very first launch.
    /// Stored as Int raw because @SceneStorage accepts that directly;
    /// `selectedTabBinding` exposes the enum form to views that need it.
    /// Fixes BUG-04 (always-lands-on-Coach) from the QA pass.
    @SceneStorage("selectedTabRaw") private var selectedTabRaw: Int = Tab.coach.rawValue
    @State private var onboardingComplete = false
    @State private var showingFocusTimer = false
    @State private var focusDuration = 25

    private var selectedTabBinding: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: selectedTabRaw) ?? .coach },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
    private var selectedTab: Tab { Tab(rawValue: selectedTabRaw) ?? .coach }

    private var hasCompletedOnboarding: Bool {
        profiles.first?.onboardingCompleted ?? false
    }

    /// Count of delivered nudges the user hasn't reacted to yet. Drives
    /// the Coach tab badge so the receipt is visible without a push.
    @Query(filter: #Predicate<Nudge> { nudge in
        nudge.statusRaw == "delivered" && nudge.userResponseRaw == nil
    }) private var unreactedNudges: [Nudge]

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
        // TabView (with its own chrome hidden) caches each tab's view
        // state across switches, so ChatView's sendTask isn't cancelled,
        // voiceModeEnabled survives, and the orb doesn't re-animate from
        // cold on every return. The previous `Group { switch }` pattern
        // tore down the non-selected subtree, which the QA audit flagged
        // as BUG-01/02/15.
        //
        // `.safeAreaInset(edge: .bottom)` places CustomTabBar as an
        // actual safe-area participant instead of an overlay — so the
        // keyboard-avoidance stack, ScrollView content inset, and
        // ChatView's input bar all honor the tab-bar height
        // automatically. Fixes BUG-11 + SMOKE-B (input bar overlapping
        // tabs) without per-child bottom-padding math.
        TabView(selection: selectedTabBinding) {
            ChatView()
                .tag(Tab.coach)
            HomeView(selectedTab: selectedTabBinding)
                .tag(Tab.home)
            CompassTabView()
                .tag(Tab.compass)
            SettingsView()
                .tag(Tab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(
                selectedTab: selectedTabBinding,
                coachBadge: unreactedNudges.count
            )
        }
        .tint(AppColors.accent)
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
        case "assistant", "chat", "coach", "nudge":
            // Nudge taps deep-link straight to Coach. The specific
            // nudge will be pinned at the top of the Coach surface
            // via the Recent Nudges section (commit 2 wires the
            // pinned-item highlight).
            selectedTabRaw = Tab.coach.rawValue
        case "schedule":
            // Schedule is now a sheet on Today. Route the user to
            // Today first, then post an event HomeView listens for
            // that auto-opens the Schedule sheet. Preserves the
            // original intent of the deep-link so TASK-category
            // notifications land in the task's schedule context,
            // not just on the Today list (fixes BUG-03 from the QA
            // audit on the IA-foundation commit).
            selectedTabRaw = Tab.home.rawValue
            NotificationCenter.default.post(name: .openScheduleSheet, object: nil)
        case "compass", "patterns":
            selectedTabRaw = Tab.compass.rawValue
        case "settings":
            selectedTabRaw = Tab.settings.rawValue
        default:
            selectedTabRaw = Tab.home.rawValue
        }
    }
}
