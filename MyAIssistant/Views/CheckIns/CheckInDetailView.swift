import SwiftUI
import SwiftData

struct CheckInDetailView: View {
    let initialSlot: CheckInTime
    @State private var timeSlot: CheckInTime
    @State private var isYesterday: Bool = false

    init(timeSlot: CheckInTime) {
        self.initialSlot = timeSlot
        _timeSlot = State(initialValue: timeSlot)
    }
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CheckInRecord> { $0.completed == true },
           sort: \CheckInRecord.date, order: .reverse) private var allCheckIns: [CheckInRecord]
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.checkInManager) private var checkInManager
    @Environment(\.usageGateManager) private var usageGateManager
    @Environment(\.notificationManager) private var notificationManager
    @Environment(\.checkInBehaviorEngine) private var checkInBehaviorEngine
    @State private var currentStep: CheckInStep = .greeting
    @State private var isGated = false
    @State private var selectedMood: Int? = nil
    @State private var selectedEnergy: Int? = nil
    @State private var notes = ""
    @State private var aiGreeting = ""
    @State private var isLoadingGreeting = true
    @State private var record: CheckInRecord?

    // Daily Recap
    @Environment(\.dailyRecapGenerator) private var recapGenerator
    @Environment(\.userName) private var userName
    @State private var recapMessage: String?
    @State private var isLoadingRecap = false

    // Habits due today
    @Query(filter: #Predicate<HabitItem> { $0.archivedAt == nil }) private var allHabits: [HabitItem]

    private enum CheckInStep {
        case greeting
        case mood
        case energy
        case notes
        case complete
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                ScrollView {
                    VStack(spacing: 24) {
                        if isGated {
                            PaywallCard(
                                title: "Check-in limit reached",
                                message: "You've used all \(AppConstants.freeCheckInsPerDay) free check-ins today. Upgrade for unlimited check-ins."
                            )

                            Button {
                                dismiss()
                            } label: {
                                Text("Close")
                                    .font(AppFonts.bodyMedium(15))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        } else {
                            switch currentStep {
                            case .greeting:
                                greetingStep
                            case .mood:
                                moodStep
                            case .energy:
                                energyStep
                            case .notes:
                                notesStep
                            case .complete:
                                completeStep
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                // Navigation buttons
                if currentStep != .complete {
                    navigationButtons
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .onAppear {
                // If the initial slot is already completed today, advance to
                // the first uncompleted slot so the user lands on something useful.
                if completedSlotsForDay.contains(timeSlot.rawValue),
                   let firstOpen = CheckInTime.allCases.first(where: { !completedSlotsForDay.contains($0.rawValue) }) {
                    timeSlot = firstOpen
                }
                if let gate = usageGateManager, !gate.canDoCheckIn(tier: tier) {
                    isGated = true
                } else {
                    loadGreeting()
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let steps: [CheckInStep] = [.greeting, .mood, .energy, .notes]
        let currentIndex = steps.firstIndex(of: currentStep) ?? 0
        let progress = currentStep == .complete ? 1.0 : Double(currentIndex) / Double(steps.count)

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 4)

                Rectangle()
                    .fill(timeSlot.color)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Greeting Step

    /// Slots already completed for the date being logged (today or yesterday).
    private var completedSlotsForDay: Set<String> {
        let cal = Calendar.current
        let dayBase = isYesterday
            ? (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            : Date()
        let start = cal.startOfDay(for: dayBase)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return Set(allCheckIns.filter { $0.date >= start && $0.date < end }.map(\.timeSlotRaw))
    }

    private var slotPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(CheckInTime.allCases) { slot in
                    let alreadyDone = completedSlotsForDay.contains(slot.rawValue)
                    Button {
                        guard !alreadyDone else { return }
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { timeSlot = slot }
                    } label: {
                        VStack(spacing: 2) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: slot.sfSymbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(timeSlot == slot && !alreadyDone ? .white : slot.color)
                                if alreadyDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(AppColors.completionGreen)
                                        .background(Circle().fill(AppColors.surface))
                                        .offset(x: 6, y: -6)
                                }
                            }
                            Text(slot.rawValue)
                                .font(AppFonts.label(10))
                                .foregroundColor(
                                    alreadyDone ? AppColors.textMuted
                                    : (timeSlot == slot ? .white : AppColors.textSecondary)
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            alreadyDone ? AppColors.surface.opacity(0.5)
                            : (timeSlot == slot ? slot.color : AppColors.surface)
                        )
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(timeSlot == slot && !alreadyDone ? Color.clear : AppColors.border, lineWidth: 1)
                        )
                        .opacity(alreadyDone ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadyDone)
                    .accessibilityLabel("\(slot.rawValue)\(alreadyDone ? ", already checked in" : "")")
                }
            }

            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { isYesterday.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isYesterday ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                    Text("Backfill yesterday")
                        .font(AppFonts.caption(12))
                }
                .foregroundColor(isYesterday ? AppColors.accent : AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    private var greetingStep: some View {
        VStack(spacing: 20) {
            slotPicker

            Image(systemName: timeSlot.sfSymbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(timeSlot.color)

            Text(timeSlot.title)
                .font(AppFonts.display(28))
                .foregroundColor(AppColors.textPrimary)

            if isLoadingGreeting {
                ProgressView()
                    .tint(timeSlot.color)
            } else {
                Text(aiGreeting)
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Mood Step

    private var moodStep: some View {
        VStack(spacing: 24) {
            Image(systemName: timeSlot.sfSymbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(timeSlot.color)

            MoodPicker(selectedMood: $selectedMood)
        }
        .padding(.top, 20)
    }

    // MARK: - Energy Step

    private var energyStep: some View {
        VStack(spacing: 20) {
            Text("Energy Level")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { level in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedEnergy = level
                        }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(
                                        selectedEnergy == level
                                            ? timeSlot.color
                                            : AppColors.surface
                                    )
                                    .frame(width: 48, height: 48)
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                selectedEnergy == level
                                                    ? Color.clear
                                                    : AppColors.border,
                                                lineWidth: 1
                                            )
                                    )

                                Text("\(level)")
                                    .font(AppFonts.bodyMedium(16))
                                    .foregroundColor(
                                        selectedEnergy == level ? .white : AppColors.textPrimary
                                    )
                            }

                            Text(energyLabel(level))
                                .font(AppFonts.caption(10))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Notes Step

    private var notesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anything on your mind?")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            Text("Optional — jot down a quick note about your day.")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)

            TextField("Today I...", text: $notes, axis: .vertical)
                .font(AppFonts.body(15))
                .lineLimit(3...6)
                .padding(14)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
        }
        .padding(.top, 20)
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 20) {
            Text("✅")
                .font(.system(size: 56))

            Text("Check-in Complete!")
                .font(AppFonts.display(24))
                .foregroundColor(AppColors.textPrimary)

            if let mood = selectedMood {
                let moods = ["", "😔", "😕", "😐", "🙂", "😄"]
                Text("Mood: \(moods[mood])  Energy: \(selectedEnergy ?? 3)/5")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
            }

            // Daily Recap Card
            if isLoadingRecap {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(AppColors.accentWarm)
                    Text("Thinking...")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Loading daily insight")
                .padding()
            } else if let recap = recapMessage {
                recapCard(recap)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.3), value: recapMessage)
            }

            // Habits due today (not yet completed)
            if !habitsDueToday.isEmpty {
                habitsDueCard
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(timeSlot.color)
                    .cornerRadius(AppRadius.md)
            }
            .padding(.top, 10)
        }
        .padding(.top, 40)
        .task {
            await generateRecap()
        }
    }

    // MARK: - Daily Recap Card

    // MARK: - Habits Due Today

    private var habitsDueToday: [HabitItem] {
        let today = Date()
        return allHabits.filter { $0.targetDays.appliesTo(date: today) && !$0.isCompletedOn(today) }
    }

    @Environment(\.habitManager) private var habitManager

    private var habitsDueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "repeat.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                    .accessibilityHidden(true)
                Text("Habits due today")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(AppColors.accent)
            }

            ForEach(habitsDueToday, id: \.id) { habit in
                HStack(spacing: 10) {
                    Text(habit.icon)
                        .font(.system(size: 20))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.title)
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.textPrimary)
                        let streak = habit.currentStreak()
                        if streak > 0 {
                            Text("\(streak)-day streak")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }

                    Spacer()

                    Button {
                        Haptics.success()
                        habitManager?.toggleCompletion(habit, for: Date())
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 24))
                            .foregroundColor(AppColors.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Complete \(habit.title)")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.accent.opacity(0.12), lineWidth: 1)
        )
    }

    private func recapCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accentWarm)
                    .accessibilityHidden(true)
                Text("I noticed something about your day")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(AppColors.accentWarm)
            }

            Text(message)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                // Dismiss check-in and navigate to AI chat with the daily recap context
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .didTapNotification,
                        object: nil,
                        userInfo: ["destination": "assistant", "category": "DAILY_RECAP", "originalUserInfo": [:] as [String: Any]]
                    )
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.caption)
                    Text("Reply")
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(AppColors.accentWarm)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppColors.accentWarm.opacity(0.1))
                .cornerRadius(AppRadius.sm)
            }
            .buttonStyle(.scale)
            .accessibilityLabel("Reply to daily insight")
            .accessibilityHint("Opens the AI chat to continue this conversation")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.accentWarm.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.accentWarm.opacity(0.15), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily insight from your assistant")
    }

    private func generateRecap() async {
        guard let generator = recapGenerator else { return }
        isLoadingRecap = true
        recapMessage = await generator.generate(
            currentTimeSlot: timeSlot,
            userName: userName,
            subscriptionTier: tier
        )
        isLoadingRecap = false
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep != .greeting {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        goBack()
                    }
                } label: {
                    Text("Back")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.border, lineWidth: 1)
                        )
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    goForward()
                }
            } label: {
                Text(currentStep == .notes ? "Complete" : "Continue")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canAdvance ? timeSlot.color : AppColors.textMuted)
                    .cornerRadius(12)
            }
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    // MARK: - Logic

    /// Anchor date for this check-in: today (or yesterday if backfilling),
    /// snapped to the slot's anchor hour so insights bucket correctly.
    private var anchorDate: Date {
        let cal = Calendar.current
        let dayBase = isYesterday
            ? (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            : Date()
        // Use bySettingHour so DST transitions don't shift the anchor by 1h.
        return cal.date(bySettingHour: timeSlot.hour, minute: 0, second: 0, of: dayBase) ?? dayBase
    }

    private var canAdvance: Bool {
        switch currentStep {
        case .greeting: return !isLoadingGreeting
        case .mood: return selectedMood != nil
        case .energy: return selectedEnergy != nil
        case .notes: return true
        case .complete: return true
        }
    }

    private func goForward() {
        switch currentStep {
        case .greeting:
            record = checkInManager?.startCheckIn(timeSlot: timeSlot, date: anchorDate)
            currentStep = .mood
        case .mood:
            currentStep = .energy
        case .energy:
            currentStep = .notes
        case .notes:
            finalizeCheckIn()
            currentStep = .complete
        case .complete:
            break
        }
    }

    private func goBack() {
        switch currentStep {
        case .mood: currentStep = .greeting
        case .energy: currentStep = .mood
        case .notes: currentStep = .energy
        default: break
        }
    }

    private func loadGreeting() {
        Task {
            if let manager = checkInManager {
                aiGreeting = await manager.generateGreeting(
                    timeSlot: timeSlot,
                    mood: nil,
                    keychain: keychainService,
                    tier: tier,
                    scheduleSummary: taskManager?.scheduleSummary() ?? "",
                    completionRate: patternEngine?.completionRate() ?? 0,
                    streak: patternEngine?.currentStreak() ?? 0
                )
            } else {
                aiGreeting = timeSlot.greeting
            }
            isLoadingGreeting = false
        }
    }

    private func finalizeCheckIn() {
        guard let record else { return }
        checkInManager?.completeCheckIn(
            record,
            mood: selectedMood ?? 3,
            energyLevel: selectedEnergy,
            notes: notes.isEmpty ? nil : notes,
            aiSummary: aiGreeting
        )
        usageGateManager?.recordCheckIn()

        // Feed the adaptive behavior engine so it can learn the user's actual
        // check-in patterns and adapt notification timing / surface suggestions.
        checkInBehaviorEngine?.recordCompletion(window: timeSlot)

        // Cancel today's streak-at-risk reminder and re-schedule adaptive reminders
        // for tomorrow based on the updated streak value
        let updatedStreak = patternEngine?.currentStreak() ?? 0
        notificationManager?.cancelStreakReminder()
        notificationManager?.scheduleAdaptiveCheckInReminders(currentStreak: updatedStreak)
    }

    private func energyLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Low"
        case 2: return "Tired"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "High"
        default: return ""
        }
    }
}
