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

    private let totalPages = 10

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back button (on screens 1-8, not Welcome or Notification)
            if currentPage > 0 && currentPage < totalPages - 1 {
                topBar
            }

            // Progress dots
            if currentPage > 0 && currentPage < totalPages - 1 {
                progressDots
                    .padding(.top, 4)
            }

            TabView(selection: $currentPage) {
                // Screen 0: Welcome
                WelcomeView(onContinue: { advance() })
                    .tag(0)

                // Screen 1: Sign in with Apple (auth + free tier unlock)
                SignInWithAppleView(
                    onSignedIn: { name in
                        // If Apple shared a name, save it and skip the name capture screen
                        if let name, !name.isEmpty {
                            capturedName = name
                            advanceBy(2)  // Skip past Name Capture (page 2)
                        } else {
                            advance()
                        }
                    },
                    onSkip: { advance() }
                )
                .tag(1)

                // Screen 2: Name Capture (skipped if Apple already provided name)
                NameCaptureView(
                    name: $capturedName,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .tag(2)

                // Screen 3: Compass Intro
                OnboardingIntroView(onContinue: { advance() })
                    .tag(3)

                // Screen 4: Quick Rate
                OnboardingQuickRateView(ratings: $ratings, onContinue: {
                    suggestedTasks = StarterTaskPool.tasksForWeakest(ratings: ratings)
                    advance()
                })
                .tag(4)

                // Screen 5: Compass Reveal
                OnboardingCompassRevealView(
                    ratings: ratings,
                    onContinue: { advance() }
                )
                .tag(5)

                // Screen 6: Intention Capture (creates SeasonGoal for Phase 1 AI)
                IntentionCaptureView(
                    weakestDimension: weakestDimension,
                    intention: $capturedIntention,
                    goalDimension: $capturedGoalDimension,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .tag(6)

                // Screen 7: Suggested Tasks
                OnboardingSuggestedTasksView(
                    tasks: suggestedTasks,
                    addedIndices: $addedTaskIndices,
                    weakestDimension: weakestDimension,
                    onContinue: { advance() }
                )
                .tag(7)

                // Screen 8: Check-in Schedule
                OnboardingScheduleView(onFinish: { advance() })
                    .tag(8)

                // Screen 9: Notification Permission (final step)
                NotificationPermissionView(
                    onAllow: { completeOnboarding() },
                    onSkip: { completeOnboarding() }
                )
                .tag(9)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
    }

    // MARK: - Navigation

    private func advance() {
        advanceBy(1)
    }

    private func advanceBy(_ steps: Int) {
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = min(currentPage + steps, totalPages - 1)
        }
    }

    private func goBack() {
        guard currentPage > 0 else { return }
        Haptics.selection()

        // Special-case the screens that we may have skipped over on the way
        // forward. If the user reached page 3 (Compass Intro) via Apple
        // sign-in (which jumps from 1 → 3), tapping back should land them
        // back on the Sign-in screen, not the skipped Name Capture screen.
        let trimmedName = capturedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let appleProvidedName = !trimmedName.isEmpty
        let target: Int
        if currentPage == 3 && appleProvidedName {
            target = 1  // back to Sign in with Apple, skipping Name Capture
        } else {
            target = currentPage - 1
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = target
        }
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
            // Map 1/3/5/7/9 to satisfaction 1-5 for the existing model
            let satisfaction = max(1, min(5, (score + 1) / 2))
            checkIn.setSatisfaction(satisfaction, for: dim)
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
