import SwiftUI
import SwiftData

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
    /// so it survives any TabView re-mount of the closing page (QA
    /// BUG-01). Without this lift, a backtrack-and-return path would
    /// reset the state machine and re-show Apple Sign-in even after
    /// successful auth.
    @State private var closingStage: OnboardingClosingView.Stage = .signIn

    /// Last-advance timestamp for the navigation throttle (QA BUG-10).
    /// Rapid back/forward taps could otherwise interrupt a mid-flight
    /// `withAnimation` and oscillate `currentPage`.
    @State private var lastNavAt: Date = .distantPast

    /// Step 2 restructure: 10-screen flow → 7-screen "value-first" flow.
    /// Sign-in moved to the closing step ("Sign in to save your Compass"
    /// is a stronger CTA than upfront auth), Name Capture absorbed into
    /// the closing step, Schedule deleted (its 4-slot context now lives
    /// inside the Notification screen via `showsScheduleContext`).
    private let totalPages = 7

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

            TabView(selection: $currentPage) {
                // Screen 0: Welcome
                WelcomeView(onContinue: { advance() })
                    .tag(0)

                // Screen 1: Compass Intro
                OnboardingIntroView(onContinue: { advance() })
                    .tag(1)

                // Screen 2: Quick Rate
                OnboardingQuickRateView(ratings: $ratings, onContinue: {
                    suggestedTasks = StarterTaskPool.tasksForWeakest(ratings: ratings)
                    advance()
                })
                .tag(2)

                // Screen 3: Compass Reveal (radar + AI voice debut)
                OnboardingCompassRevealView(
                    ratings: ratings,
                    onContinue: { advance() }
                )
                .tag(3)

                // Screen 4: Intention Capture (creates SeasonGoal for Phase 1 AI)
                IntentionCaptureView(
                    weakestDimension: weakestDimension,
                    intention: $capturedIntention,
                    goalDimension: $capturedGoalDimension,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .tag(4)

                // Screen 5: Suggested Tasks
                OnboardingSuggestedTasksView(
                    tasks: suggestedTasks,
                    addedIndices: $addedTaskIndices,
                    weakestDimension: weakestDimension,
                    onContinue: { advance() }
                )
                .tag(5)

                // Screen 6: Combined SignIn + Name + Notification (closing
                // step). Internal state machine — see OnboardingClosingView.
                // Stage is bound from the container so a re-mount doesn't
                // reset the user's progress through the sub-stages.
                OnboardingClosingView(
                    capturedName: $capturedName,
                    stage: $closingStage,
                    onComplete: { completeOnboarding() }
                )
                .tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Disable user-driven horizontal swipe between onboarding
            // pages — each screen has its own Continue / Skip gates that
            // validate input. Swipe let users bypass e.g. NameCapture
            // validation or the intent required before screen 6. Pages
            // still advance programmatically via `advance()`.
            //
            // `simultaneousGesture` runs alongside the page TabView's
            // own DragGesture and consumes the events deterministically,
            // closing the iOS-version-dependent gap where a plain
            // `.gesture` would lose precedence (QA BUG-07).
            .simultaneousGesture(DragGesture().onChanged { _ in })
            .animation(.easeInOut(duration: 0.3), value: currentPage)
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
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = min(currentPage + steps, totalPages - 1)
        }
    }

    private func goBack() {
        guard currentPage > 0 else { return }
        guard !isNavThrottled() else { return }
        Haptics.selection()

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

        withAnimation(.easeInOut(duration: 0.4)) {
            onboardingComplete = true
        }
    }
}
