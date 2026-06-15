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
    @SceneStorage("selectedTabRaw") private var selectedTabRaw: Int = AppTab.coach.rawValue
    @State private var onboardingComplete = false
    @State private var showingFocusTimer = false
    @State private var focusDuration = 25
    /// Habit id to focus in HomeView's Habits sheet after a
    /// `windowedHabit` "Do now" action. Owned by ContentView because
    /// HomeView may not yet be materialized when the request arrives
    /// (first-launch user on Coach tab has never visited Home, so
    /// `.onReceive` subscribers on HomeView haven't registered). State
    /// here persists across the tab switch and HomeView consumes it
    /// on first appear.
    @State private var pendingFocusedHabitID: String?
    /// True while a software keyboard is actually occluding the
    /// bottom of the window. Updated from `keyboardWillChangeFrame`
    /// so hardware/Bluetooth/undocked iPad keyboards (which fire
    /// willShow with zero-height frames) don't falsely trigger the
    /// tab-bar hide.
    @State private var isKeyboardVisible = false

    /// Hide the tab bar on every tab while the keyboard is up.
    /// Matches iOS convention (Messages, Mail, Slack all hide their
    /// tab bar / bottom chrome during keyboard) and is required to
    /// avoid a 60pt dead strip above the keyboard: the tab-bar
    /// overlay rises with the keyboard via default avoidance while
    /// the per-tab `tabBarSpacer` inset also reserves 60pt, so a
    /// keyboard-up state on Home/Compass/Settings would otherwise
    /// show the tab bar floating above a visible empty band. Keyboard
    /// is dismissed on tab switch (see `.onChange` below) so the bar
    /// is back by the time the user lands. QA BUG-02/03.
    private var shouldHideTabBarForKeyboard: Bool {
        isKeyboardVisible
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { AppTab(rawValue: selectedTabRaw) ?? .coach },
            set: { selectedTabRaw = $0.rawValue }
        )
    }
    private var selectedTab: AppTab { AppTab(rawValue: selectedTabRaw) ?? .coach }

    /// Wraps a tab's root view so non-selected tabs stay mounted (state
    /// preserved) but invisible + non-interactive. `allowsHitTesting`
    /// stops touches from leaking through to hidden subtrees;
    /// `.accessibilityHidden` keeps VoiceOver focused on the visible tab.
    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isVisible = selectedTab == tab
        content()
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
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
        // Custom tab chrome only. A hidden native `TabView` used to sit
        // behind this bar for state caching, but iOS 26's Liquid Glass
        // leaks `_UITabBarPlatterView` through `.toolbar(.hidden,
        // for: .tabBar)`, which shows up as a blank draggable pill above
        // our tab bar. The ZStack keeps all tab subtrees mounted so
        // ChatView state survives tab switches, while avoiding native
        // tab-bar rendering entirely.
        VStack(spacing: 0) {
            ZStack {
                tabContent(.coach)  { ChatView() }
                tabContent(.home)   {
                    HomeView(
                        selectedTab: selectedTabBinding,
                        pendingFocusedHabitID: $pendingFocusedHabitID
                    )
                }
                tabContent(.compass)  { CompassTabView() }
                tabContent(.settings) { SettingsView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !shouldHideTabBarForKeyboard {
                CustomTabBar(
                    selectedTab: selectedTabBinding,
                    coachBadge: unreactedCount
                )
                .transition(.opacity)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .openHabitsFocused)) { note in
            // "Do now" on a windowed-habit nudge. ContentView owns both
            // the tab switch AND the pending focus id — storing the id
            // here (not in HomeView's .onReceive) closes the cold-launch
            // gap where HomeView hadn't mounted yet and dropped the
            // post. HomeView reads the binding on appear + via
            // .onChange, then nils it back out to consume.
            guard let habitID = note.userInfo?["habitID"] as? String,
                  !habitID.isEmpty else { return }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            pendingFocusedHabitID = habitID
            if selectedTabRaw != AppTab.home.rawValue {
                selectedTabRaw = AppTab.home.rawValue
            }
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
            // Threshold at 60pt catches short-screen + predictive-bar
            // cases (iPhone SE, 16e with Bluetooth keyboard + predictive
            // row ~80pt) where the keyboard partially occludes the
            // composer but didn't trip the old 100pt gate. Still
            // rejects iPad's floating assistive bar (~44pt) and pure
            // hardware-keyboard cases (0pt). (BUG-04)
            //
            // Animate in lockstep with the system keyboard: pull the
            // duration the keyboard is actually using out of userInfo
            // rather than hardcoding 0.2s. Matches the keyboard curve
            // closely enough that the tab-bar inset and the keyboard
            // slide as one.
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                isKeyboardVisible = overlap > 60
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
            withAnimation(.easeInOut(duration: duration)) {
                isKeyboardVisible = false
            }
        }
        .onChange(of: selectedTabRaw) { _, _ in
            // Dismiss keyboard on tab switch so the destination tab
            // renders with its chrome in the normal state. Without
            // this, a Coach-tab composition followed by a fast tap
            // on Home could leave the keyboard up briefly, tab bar
            // hidden on the new tab, then a flicker when the
            // keyboard finally resigned. QA BUG-04.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
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
            selectedTabRaw = AppTab.coach.rawValue
        case "schedule":
            // Schedule is now a sheet on Today. Route the user to
            // Today first, then post an event HomeView listens for
            // that auto-opens the Schedule sheet. Preserves the
            // original intent of the deep-link so TASK-category
            // notifications land in the task's schedule context,
            // not just on the Today list (fixes BUG-03 from the QA
            // audit on the IA-foundation commit).
            selectedTabRaw = AppTab.home.rawValue
            NotificationCenter.default.post(name: .openScheduleSheet, object: nil)
        case "compass", "patterns":
            selectedTabRaw = AppTab.compass.rawValue
        case "settings":
            selectedTabRaw = AppTab.settings.rawValue
        default:
            selectedTabRaw = AppTab.home.rawValue
        }
    }
}
