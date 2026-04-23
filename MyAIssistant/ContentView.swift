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
    /// True while a software keyboard is actually occluding the
    /// bottom of the window. Updated from `keyboardWillChangeFrame`
    /// so hardware/Bluetooth/undocked iPad keyboards (which fire
    /// willShow with zero-height frames) don't falsely trigger the
    /// tab-bar hide.
    @State private var isKeyboardVisible = false
    /// Baseline tab bar height that scales with Dynamic Type. Tied
    /// to `.body` because the tab bar's dominant metric is the
    /// 22pt icon (`AppFonts.heading(22)`), which scales with body-
    /// class types — caption-relative under-reserved at AX sizes
    /// and re-opened the composer occlusion bug.
    @ScaledMetric(relativeTo: .body) private var tabBarBaseHeight: CGFloat = 64

    /// Only hide the tab bar for keyboard when the user is on the
    /// Coach tab — that's the only tab whose input bar sits flush
    /// against the tab bar. On Home/Compass/Settings the keyboard
    /// rises over unrelated content; hiding global navigation there
    /// just removes an affordance users still need. QA BUG-01.
    private var shouldHideTabBarForKeyboard: Bool {
        isKeyboardVisible && selectedTab == .coach
    }

    private var selectedTabBinding: Binding<Tab> {
        Binding(
            get: { Tab(rawValue: selectedTabRaw) ?? .coach },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
    private var selectedTab: Tab { Tab(rawValue: selectedTabRaw) ?? .coach }

    /// Height reservation for the CustomTabBar inside each tab's
    /// content. Scales with Dynamic Type via `tabBarBaseHeight`
    /// (@ScaledMetric) so Larger Accessibility Sizes don't
    /// reintroduce the composer occlusion this fix closed. Collapses
    /// to 0 when the keyboard is visible so the input bar sits flush
    /// with the keyboard top — the overlay bar also hides behind the
    /// keyboard so no chrome is lost.
    private var tabBarSpacer: some View {
        Color.clear
            .frame(height: shouldHideTabBarForKeyboard ? 0 : tabBarBaseHeight)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .animation(.easeOut(duration: 0.2), value: shouldHideTabBarForKeyboard)
    }

    private var hasCompletedOnboarding: Bool {
        profiles.first?.onboardingCompleted ?? false
    }

    /// All nudges sorted newest first; filtering to delivered-unreacted
    /// happens in `unreactedCount` below. Plain-closure filter (not
    /// a `#Predicate` literal) so we can reference the enum raw value
    /// and catch any future rename at compile time — fix for BUG-02.
    /// The query is unbounded here because the Nudge table is expected
    /// to stay small (≤ ~dozens over a dogfood month); revisit with a
    /// date-bounded FetchDescriptor if a power user ever crosses ~1k.
    @Query(sort: [SortDescriptor(\Nudge.createdAt, order: .reverse)])
    private var allNudges: [Nudge]

    private var unreactedCount: Int {
        let deliveredRaw = NudgeStatus.delivered.rawValue
        return allNudges.reduce(0) { acc, nudge in
            acc + ((nudge.statusRaw == deliveredRaw && nudge.userResponseRaw == nil) ? 1 : 0)
        }
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
        // TabView (with its own chrome hidden) caches each tab's view
        // state across switches, so ChatView's sendTask isn't cancelled,
        // voiceModeEnabled survives, and the orb doesn't re-animate from
        // cold on every return. The previous `Group { switch }` pattern
        // tore down the non-selected subtree, which the QA audit flagged
        // as BUG-01/02/15.
        //
        // CustomTabBar is an overlay + per-tab `safeAreaInset` spacer
        // (not `safeAreaInset` on the TabView) because on iOS 17
        // TabView does NOT propagate its own bottom inset into each
        // tab's safe-area stack — children still see the original
        // window safe area, so ChatView's input bar was rendering
        // underneath the tab bar (user report 2026-04-23, second
        // occurrence). The per-tab spacer reserves real layout space
        // inside each child; the overlay draws the actual chrome.
        TabView(selection: selectedTabBinding) {
            ChatView()
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBarSpacer }
                .tag(Tab.coach)
            HomeView(selectedTab: selectedTabBinding)
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBarSpacer }
                .tag(Tab.home)
            CompassTabView()
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBarSpacer }
                .tag(Tab.compass)
            SettingsView()
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBarSpacer }
                .tag(Tab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            // Hide the tab bar entirely while the keyboard is up. iOS
            // keyboard avoidance lifts the overlay above the keyboard,
            // which ends up occluding ChatView's composer (user report
            // 2026-04-23, 3rd pass). Matches Messages/Mail — the tab
            // bar is gone while typing and returns on dismiss.
            if !shouldHideTabBarForKeyboard {
                CustomTabBar(
                    selectedTab: selectedTabBinding,
                    coachBadge: unreactedCount
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shouldHideTabBarForKeyboard)
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
        // `keyboardWillChangeFrame` instead of `willShow`/`willHide`
        // so hardware/Bluetooth keyboards and undocked/floating iPad
        // keyboards (which report a zero- or off-screen frame) don't
        // flip `isKeyboardVisible` true when they don't actually
        // occlude the composer. We only treat the keyboard as visible
        // when its final frame overlaps the window's bottom by a
        // meaningful amount (> 100pt — excludes the floating-bar
        // assistant-predictive row on some iPad configs).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            let endFrame = frameValue.cgRectValue
            // Use the active window scene's screen height rather than
            // UIScreen.main (deprecated iOS 16+, wrong on Stage Manager
            // and multi-window iPad where the window frame differs from
            // the full display). Keyboard notification frames are still
            // in screen coordinates, so we compare against screen height.
            let screenHeight = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds.height ?? UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - endFrame.origin.y)
            withAnimation(.easeOut(duration: 0.2)) {
                isKeyboardVisible = overlap > 100
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                isKeyboardVisible = false
            }
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
        // If a focus session is open, dismiss it so the user actually
        // sees the tab they were routed to. Without this, a nudge
        // deep-link during focus silently swaps the tab behind the
        // sheet and the user sees no change. Fix for QA BUG-05 on
        // the overlay+spacer migration.
        if showingFocusTimer {
            showingFocusTimer = false
        }
        // Resign first responder so a notification tap during
        // ChatView composition doesn't leave the keyboard up after
        // the tab switch — the destination tab would otherwise
        // render with both the wrong chrome (no tab bar, per
        // shouldHideTabBarForKeyboard) and a dangling keyboard the
        // user didn't initiate. QA BUG-07.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
