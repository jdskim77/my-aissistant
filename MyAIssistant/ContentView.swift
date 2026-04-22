import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.networkMonitor) private var networkMonitor
    @Query private var profiles: [UserProfile]
    // Default to Coach tab. The IA promise is coach-first — landing
    // returning users on Coach (with the last nudge pinned) reinforces
    // it immediately. Revisit after dogfood Week 1 if the pattern feels
    // wrong for mornings.
    @State private var selectedTab: Tab = .coach
    @State private var onboardingComplete = false
    @State private var showingFocusTimer = false
    @State private var focusDuration = 25

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
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .coach:
                    // Coach is now a first-class tab surface, not a sheet.
                    // Passing no onDismiss tells ChatView to hide the
                    // chevron-down close button — there's nothing to
                    // dismiss when the chat is the destination.
                    ChatView()
                case .home:
                    HomeView(selectedTab: $selectedTab)
                case .compass:
                    CompassTabView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // CustomTabBar is ~70pt tall (no more center-button lift).
            // Keep 80pt of bottom padding so content never clips behind
            // the bar on devices with a home indicator.
            .padding(.bottom, 80)

            CustomTabBar(
                selectedTab: $selectedTab,
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
            selectedTab = .coach
        case "schedule":
            // Schedule is now a sheet on Today. Route users there
            // and let them tap the calendar icon if they want the
            // full week/month view.
            selectedTab = .home
        case "compass", "patterns":
            selectedTab = .compass
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .home
        }
    }
}
