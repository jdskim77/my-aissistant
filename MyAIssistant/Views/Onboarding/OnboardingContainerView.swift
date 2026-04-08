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

    private let totalPages = 9

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            if currentPage > 0 && currentPage < totalPages - 1 {
                progressDots
                    .padding(.top, 12)
            }

            TabView(selection: $currentPage) {
                // Screen 0: Welcome
                WelcomeView(onContinue: { advance() })
                    .tag(0)

                // Screen 1: Name Capture (NEW — personalize AI from msg 1)
                NameCaptureView(
                    name: $capturedName,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .tag(1)

                // Screen 2: Compass Intro
                OnboardingIntroView(onContinue: { advance() })
                    .tag(2)

                // Screen 3: Quick Rate
                OnboardingQuickRateView(ratings: $ratings, onContinue: {
                    suggestedTasks = StarterTaskPool.tasksForWeakest(ratings: ratings)
                    advance()
                })
                .tag(3)

                // Screen 4: Compass Reveal
                OnboardingCompassRevealView(
                    ratings: ratings,
                    onContinue: { advance() }
                )
                .tag(4)

                // Screen 5: Intention Capture (NEW — creates SeasonGoal for Phase 1 AI)
                IntentionCaptureView(
                    weakestDimension: weakestDimension,
                    intention: $capturedIntention,
                    goalDimension: $capturedGoalDimension,
                    onContinue: { advance() },
                    onSkip: { advance() }
                )
                .tag(5)

                // Screen 6: Suggested Tasks
                OnboardingSuggestedTasksView(
                    tasks: suggestedTasks,
                    addedIndices: $addedTaskIndices,
                    weakestDimension: weakestDimension,
                    onContinue: { advance() }
                )
                .tag(6)

                // Screen 7: Check-in Schedule (now advances instead of finishing)
                OnboardingScheduleView(onFinish: { advance() })
                    .tag(7)

                // Screen 8: Notification Permission (NEW — final step)
                NotificationPermissionView(
                    onAllow: { completeOnboarding() },
                    onSkip: { completeOnboarding() }
                )
                .tag(8)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
        }
        .background(AppColors.background.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
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
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = min(currentPage + 1, totalPages - 1)
        }
    }

    private var weakestDimension: LifeDimension {
        StarterTaskPool.weakestDimension(from: ratings)
    }

    // MARK: - Complete Onboarding

    private func completeOnboarding() {
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
        modelContext.safeSave()

        withAnimation(.easeInOut(duration: 0.4)) {
            onboardingComplete = true
        }
    }
}
