import SwiftUI
import SwiftData
import UserNotifications

struct OnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var onboardingComplete: Bool
    @State private var currentPage = 0
    @State private var ratings: [LifeDimension: Int] = [:]
    @State private var addedTaskIndices: Set<Int> = []
    @State private var appeared = false

    /// Captured during the new onboarding screens (Phase 1 AI context).
    @State private var capturedName: String = ""
    @State private var capturedIntention: String = ""
    @State private var capturedGoalDimension: LifeDimension = .physical

    /// The starter task templates selected for the weakest dimension
    @State private var suggestedTasks: [StarterTask] = []

    /// Re-entrancy guard for completeOnboarding (prevents double-tap duplicates).
    @State private var isCompleting = false

    /// Save error surfaced via alert when SwiftData persistence fails.
    @State private var saveErrorMessage: String?

    /// Closing-screen stage. Owned here (not inside OnboardingClosingView)
    /// so it survives any re-mount of the closing page (QA
    /// BUG-01). Without this lift, a backtrack-and-return path would
    /// reset the state machine and re-show Apple Sign-in even after
    /// successful auth.
    @State private var closingStage: OnboardingClosingView.Stage = .signIn

    /// Last-advance timestamp for the navigation throttle (QA BUG-10).
    /// Rapid back/forward taps could otherwise interrupt a mid-flight
    /// `withAnimation` and oscillate `currentPage`.
    @State private var lastNavAt: Date = .distantPast

    /// Direction of the last navigation so the manual page container slides
    /// the incoming screen in from the correct edge (forward = in from the
    /// trailing edge, back = in from leading). Replaces the directional
    /// swipe the page `TabView` used to provide for free.
    @State private var navDirection: NavDirection = .forward

    private enum NavDirection { case forward, backward }

    /// Step 2 restructure: 10-screen flow → 7-screen "value-first" flow.
    /// Sign-in moved to the closing step ("Sign in to save your Compass"
    /// is a stronger CTA than upfront auth), Name Capture absorbed into
    /// the closing step, Schedule deleted (its 4-slot context now lives
    /// inside the Notification screen via `showsScheduleContext`).
    ///
    /// 8-screen "spine-on" flow: Coach Reach inserted after Intention so
    /// the user consents to proactive nudges *while* the intention they
    /// just typed is in their head. Without this screen the proactive
    /// pillar shipped dark — `nudgeEnabledKey` defaulted to false and no
    /// other onboarding step set it true.
    private let totalPages = 8

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back button on intermediate screens only.
            // Welcome (page 0) has no back; closing step (page 6) is
            // mid-stage-machine and shouldn't surface a generic back.
            if currentPage > 0 && currentPage < totalPages - 1 {
                topBar
            }

            // Progress dots — same window as the back button.
            if currentPage > 0 && currentPage < totalPages - 1 {
                progressDots
                    .padding(.top, 4)
            }

            // Manual page container — NOT a `TabView`. A native page-style
            // `TabView` wraps a `UIPageViewController` whose chrome can leak
            // the iOS 26 Liquid Glass lens (a draggable pill) — the same bug
            // class fixed on the main tab bar. It also shipped a horizontal
            // swipe that let users bypass each screen's Continue / Skip
            // validation gates, which the old code had to suppress with a
            // `.simultaneousGesture(DragGesture())` hack. Rendering only the
            // current page in a ZStack removes both: there is no system pager
            // to leak and no swipe to gate. Pages advance only via
            // `advance()` / `goBack()`; per-page input (ratings, intention,
            // name, closing stage) is held in this container's @State, so
            // re-mounting a page on navigation preserves the user's data.
            ZStack {
                pageView(for: currentPage)
                    .id(currentPage)
                    .transition(pageTransition)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(AppColors.background.ignoresSafeArea())
        .alert("Setup Failed", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    // MARK: - Pages

    /// The screen for a given step. Switch-based (one page mounted at a
    /// time) rather than a `TabView` of tagged children — see the container
    /// comment in `body`. Per-page input lives in this container's @State,
    /// so re-mounting a page on navigation preserves the user's data.
    @ViewBuilder
    private func pageView(for page: Int) -> some View {
        switch page {
        case 0:
            WelcomeView(onContinue: { advance() })
        case 1:
            OnboardingIntroView(onContinue: { advance() })
        case 2:
            OnboardingQuickRateView(ratings: $ratings, onContinue: {
                suggestedTasks = StarterTaskPool.tasksForWeakest(ratings: ratings)
                advance()
            })
        case 3:
            OnboardingCompassRevealView(
                ratings: ratings,
                onContinue: { advance() }
            )
        case 4:
            IntentionCaptureView(
                weakestDimension: weakestDimension,
                intention: $capturedIntention,
                goalDimension: $capturedGoalDimension,
                onContinue: { advance() },
                onSkip: { advance() }
            )
        case 5:
            // Coach Reach consent — sets `nudgeEnabledKey` / `nudgeFrequencyKey`
            // so the proactive pillar is ON when onboarding ends. Placed after
            // Intention so the framing ("your coach will check in about X") is
            // concrete.
            OnboardingCoachReachView(
                weakestDimension: weakestDimension,
                intention: capturedIntention,
                onContinue: { advance() }
            )
        case 6:
            OnboardingSuggestedTasksView(
                tasks: suggestedTasks,
                addedIndices: $addedTaskIndices,
                weakestDimension: weakestDimension,
                onContinue: { advance() }
            )
        default:
            // Screen 7: Combined SignIn + Name + Notification (closing step).
            // Internal state machine — see OnboardingClosingView. Stage is
            // bound from the container so a re-mount doesn't reset the user's
            // progress through the sub-stages.
            OnboardingClosingView(
                capturedName: $capturedName,
                stage: $closingStage,
                onComplete: { completeOnboarding() }
            )
        }
    }

    /// Slide direction for the page transition, chosen from the last
    /// navigation so forward feels like advancing and back like retreating.
    private var pageTransition: AnyTransition {
        switch navDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(1..<totalPages, id: \.self) { i in
                Capsule()
                    .fill(i <= currentPage ? AppColors.accent : AppColors.border)
                    .frame(width: i == currentPage ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding step \(currentPage)")
    }

    // MARK: - Navigation

    private func advance() {
        advanceBy(1)
    }

    private func advanceBy(_ steps: Int) {
        guard !isNavThrottled() else { return }
        Haptics.light()
        navDirection = .forward
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = min(currentPage + steps, totalPages - 1)
        }
    }

    private func goBack() {
        guard currentPage > 0 else { return }
        guard !isNavThrottled() else { return }
        Haptics.selection()
        navDirection = .backward

        // Linear back. The Apple-name skip-special-casing from the prior
        // 10-screen flow is gone — Sign-in and Name Capture now live
        // inside the closing step (page 6), so there's no jump for the
        // back button to compensate for.
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = max(0, currentPage - 1)
        }
    }

    /// Soft throttle on page navigation. Rapid back/forward taps could
    /// otherwise interrupt a mid-flight `withAnimation` and oscillate
    /// `currentPage` (QA BUG-10). 320ms matches the 0.3s page-transition
    /// duration plus a small buffer.
    private func isNavThrottled() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastNavAt) < 0.32 { return true }
        lastNavAt = now
        return false
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .font(AppFonts.bodyMedium(17))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Go back")
            .accessibilityHint("Returns to the previous step")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var weakestDimension: LifeDimension {
        StarterTaskPool.weakestDimension(from: ratings)
    }

    // MARK: - Complete Onboarding

    private func completeOnboarding() {
        // Re-entrancy guard — prevent double-tap from creating duplicate records
        guard !isCompleting else { return }
        isCompleting = true

        Haptics.success()

        // 1. Save dimension ratings as a DailyBalanceCheckIn
        let checkIn = DailyBalanceCheckIn(date: Date())
        for (dim, score) in ratings {
            // Store the raw 1-9 rating directly. BalanceManager normalizes
            // to 0-10 by handling both 1-5 (daily check-ins) and 1-9
            // (onboarding) scales via: min(rating, 9) / 9.0 * 10.
            checkIn.setSatisfaction(score, for: dim)
        }
        modelContext.insert(checkIn)

        // 2. Create selected starter tasks
        let today = Date()
        let calendar = Calendar.current
        for index in addedTaskIndices.sorted() {
            guard index < suggestedTasks.count else { continue }
            let template = suggestedTasks[index]
            // Spread tasks across next 3 days
            let dayOffset = index % 3
            let taskDate = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today

            let task = TaskItem(
                title: template.title,
                category: .personal,
                priority: .medium,
                date: taskDate,
                icon: template.icon
            )
            task.dimension = template.dimension
            task.effort = .light
            modelContext.insert(task)
        }

        // 3. Persist captured intention as a SeasonGoal (Phase 1 AI context)
        let trimmedIntention = capturedIntention.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIntention.isEmpty {
            let goal = SeasonGoal(
                dimension: capturedGoalDimension,
                intention: trimmedIntention
            )
            modelContext.insert(goal)
        }

        // 4. Mark onboarding complete + persist captured display name
        let trimmedName = capturedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            profile.onboardingCompleted = true
            if !trimmedName.isEmpty {
                profile.displayName = trimmedName
            }
        } else {
            let profile = UserProfile(
                displayName: trimmedName,
                onboardingCompleted: true
            )
            modelContext.insert(profile)
        }

        // 5. Save and bail loudly on failure — don't advance to home with no data persisted
        guard modelContext.safeSave() else {
            isCompleting = false
            saveErrorMessage = "Couldn't save your setup. Please check your storage space and try again."
            return
        }

        // 6. Day-2 morning nudge — proves Pillar 1 (proactive coaching) on
        //    the user's second day without waiting for any rule to fire.
        //    Hardcoded copy referencing the captured intention (or the
        //    weakest dimension as fallback). Only scheduled if the user
        //    consented via OnboardingCoachReachView.
        scheduleDayTwoNudgeIfConsented()

        withAnimation(.easeInOut(duration: 0.4)) {
            onboardingComplete = true
        }
    }

    /// Schedules a single one-shot local notification for ~9 AM tomorrow
    /// referencing the user's captured intention (or weakest dimension).
    /// Idempotent — uses a stable identifier and removes any prior copy
    /// before adding, so a repeated onboarding pass won't stack pings.
    /// No-op when the user picked "Not now" on the Coach Reach screen.
    private func scheduleDayTwoNudgeIfConsented() {
        let nudgesEnabled = UserDefaults.standard.bool(forKey: AppConstants.nudgeEnabledKey)
        let center = UNUserNotificationCenter.current()
        let identifier = "onboarding-day2-nudge"

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard nudgesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Thrivn"
        content.body = dayTwoNudgeBody()
        content.sound = .default
        content.categoryIdentifier = AppConstants.nudgeNotificationCategory
        content.userInfo = [
            "nudgeID": identifier,
            "nudgeCategory": "onboardingDayTwo"
        ]

        // Tomorrow at 9 AM local. Calendar-based so DST and timezone shifts
        // are handled by the system, not us.
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) else { return }
        var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    private func dayTwoNudgeBody() -> String {
        let trimmed = capturedIntention.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return "Yesterday you said: \(trimmed). Take 5 minutes on it now?"
        }
        return "Five minutes on \(weakestDimension.label.lowercased()) this morning — just one small thing."
    }
}
