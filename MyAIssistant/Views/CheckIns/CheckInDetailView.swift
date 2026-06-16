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
    @FocusState private var notesFocused: Bool
    @State private var aiGreeting = ""
    @State private var isLoadingGreeting = true
    @State private var record: CheckInRecord?

    // Daily Recap
    @Environment(\.dailyRecapGenerator) private var recapGenerator
    @Environment(\.userName) private var userName
    @State private var recapMessage: String?
    @State private var isLoadingRecap = false
    /// True when `recapMessage` is the hardcoded `SafeResourceCopy.message()`
    /// returned by the crisis gate in `DailyRecapGenerator` (BUG-03 fix
    /// from the recap-gate QA pass). Drives a distinct card variant —
    /// safety framing, hotline link, no "Reply" affordance — so VoiceOver
    /// users don't hear "Daily insight from your assistant" when they're
    /// actually being shown crisis resources, and so the URL in the body
    /// is a tappable Link instead of plain text.
    @State private var isSafetyRecap = false
    /// Surfaces a brief "switched to <slot>" banner when the user tapped an
    /// already-completed slot and we auto-advanced to the next open one.
    @State private var didAutoAdvanceSlot = false
    /// True during the 250ms beat between a tap on mood/energy and the
    /// auto-advance to the next step. Locks the picker buttons so a
    /// fast double-tap can't skip a step, and hides the redundant
    /// Continue button on these steps (since the tap *is* the answer).
    @State private var isAdvancing = false
    /// Generation counter for auto-advance. Each `scheduleAutoAdvance`
    /// call increments it; the awaiting task captures its own generation
    /// and only commits the advance if the counter still matches. This
    /// closes a race that `Task.cancel()` alone can't: cancel is async
    /// and the sleeping task may have already passed `isCancelled` by
    /// the time we cancel it. Generation match is a synchronous fence.
    @State private var advanceGeneration = 0
    /// Per-tap counter wired into `.sensoryFeedback(.selection, trigger:)`
    /// on the energy step so re-tapping the SAME value still fires a
    /// haptic (e.g. after Back-nav from notes). `trigger:` only fires
    /// on value change — using `selectedEnergy` as the trigger swallows
    /// haptics on identical re-taps. MoodPicker has its own internal
    /// counter for the same reason. BUG-06 from the auto-advance QA pass.
    @State private var hapticTickEnergy = 0

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
                // Context header + progress bar
                if !isGated && currentStep != .complete {
                    progressHeader
                }

                // Auto-advance notice — only when we silently swapped the
                // user's originally-requested (already-completed) slot for
                // the next open one. VoiceOver also announces the swap.
                if didAutoAdvanceSlot {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.system(size: 14))
                        Text("Switched to \(timeSlot.rawValue) — the one you picked is already done.")
                            .font(AppFonts.caption(12))
                        Spacer()
                    }
                    .foregroundColor(timeSlot.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(timeSlot.color.opacity(0.08))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

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
            .navigationTitle("\(timeSlot.rawValue) Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppColors.textSecondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { notesFocused = false }
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(timeSlot.color)
                }
            }
            .onAppear {
                // If the initial slot is already completed today, advance to
                // the first uncompleted slot so the user lands on something useful.
                // A VoiceOver announcement + brief visible banner tells the user
                // what happened — silent slot-swap previously confused users who
                // opened "Morning" at 4pm and wondered why they were in "Afternoon".
                if completedSlotsForDay.contains(timeSlot.rawValue),
                   let firstOpen = CheckInTime.allCases.first(where: { !completedSlotsForDay.contains($0.rawValue) }) {
                    let originalLabel = timeSlot.rawValue
                    timeSlot = firstOpen
                    didAutoAdvanceSlot = true
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: "\(originalLabel) check-in already done. Switched to \(firstOpen.rawValue)."
                    )
                    // Auto-hide the banner after 4 seconds so it doesn't hang
                    // around for the whole session.
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { didAutoAdvanceSlot = false }
                    }
                }
                if let gate = usageGateManager, !gate.canDoCheckIn(tier: tier) {
                    isGated = true
                } else {
                    loadGreeting()
                }
            }
            .onDisappear {
                // Sheet dismissed mid-beat → cancel pending auto-advance
                // so it can't fire goForward against torn-down state.
                cancelPendingAdvance()
            }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        let steps: [CheckInStep] = [.greeting, .mood, .energy, .notes]
        let currentIndex = steps.firstIndex(of: currentStep) ?? 0
        let stepNumber = currentIndex + 1
        // Reserve 20% for the implicit save action so the notes step doesn't
        // mislead users into thinking they're already done.
        let progress = Double(stepNumber) / Double(steps.count + 1)
        let progressPercent = Int(progress * 100)
        let labelColor = isYesterday ? AppColors.warning : AppColors.textSecondary

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: timeSlot.sfSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(labelColor)
                    .accessibilityHidden(true)

                Text("\(timeSlot.rawValue) Check-in")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(labelColor)

                Text("·")
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textMuted)

                Text(isYesterday ? "Yesterday" : "Today")
                    .font(AppFonts.body(13))
                    .foregroundColor(labelColor)

                Spacer()

                Text("Step \(stepNumber) of \(steps.count)")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            GeometryReader { geo in
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timeSlot.rawValue) check-in for \(isYesterday ? "yesterday" : "today"), step \(stepNumber) of \(steps.count)")
        .accessibilityValue("\(progressPercent) percent complete")
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
                HStack(spacing: 8) {
                    Image(systemName: isYesterday ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                        .font(.system(size: 15))
                    Text(isYesterday ? "Logging for yesterday" : "Log for yesterday instead")
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(isYesterday ? AppColors.accent : AppColors.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isYesterday ? AppColors.accentLight : AppColors.card)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isYesterday ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.scale)
            .padding(.top, 4)
        }
    }

    private var greetingStep: some View {
        VStack(spacing: 24) {
            slotPicker

            if isLoadingGreeting {
                ProgressView()
                    .tint(timeSlot.color)
                    .padding(.top, 24)
            } else {
                Text(aiGreeting)
                    .font(AppFonts.body(16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Mood Step

    private var moodStep: some View {
        VStack(spacing: 24) {
            Image(systemName: timeSlot.sfSymbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(timeSlot.color)

            MoodPicker(
                selectedMood: $selectedMood,
                onSelect: { _ in scheduleAutoAdvance() },
                isLocked: isAdvancing
            )
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
                        guard !isAdvancing else { return }
                        hapticTickEnergy &+= 1
                        withAnimation(.spring(response: 0.3)) {
                            selectedEnergy = level
                        }
                        scheduleAutoAdvance()
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
        .sensoryFeedback(.selection, trigger: hapticTickEnergy)
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
                .focused($notesFocused)
                .padding(14)
                .background(AppColors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border, lineWidth: 1)
                )
                // Free-text mood/journal content — redact under Sensitive
                // Content (screen recording, screenshare, AssistiveTouch
                // overlay capture). Privacy is the wedge per CLAUDE.md.
                .privacySensitive()
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
                Group {
                    if isSafetyRecap {
                        safetyResourceCard(recap)
                    } else {
                        recapCard(recap)
                    }
                }
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
                // Dismiss check-in and navigate to AI chat with the daily recap context.
                // We post the route BEFORE dismiss so observers see it during the dismiss
                // transition — avoids the race where a user quickly taps another tab
                // during a timer delay and then has the chat tab yanked out from under them.
                NotificationCenter.default.post(
                    name: .didTapNotification,
                    object: nil,
                    userInfo: ["destination": "assistant", "category": "DAILY_RECAP", "originalUserInfo": [:] as [String: Any]]
                )
                dismiss()
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

    /// Card variant shown when the recap is the hardcoded
    /// `SafeResourceCopy.message()` returned by the crisis gate. Distinct
    /// from `recapCard` in three ways that matter for safety:
    ///
    ///   1. Header reads "Support resources" instead of "I noticed
    ///      something about your day" — VoiceOver announces the actual
    ///      framing, not the daily-insight framing.
    ///   2. The hotline URL from `SafeResourceCopy.actionURL()` is a
    ///      tappable `Link` (opens in Safari) instead of being plain
    ///      text inside the body string.
    ///   3. There is NO "Reply" button. Conversational follow-up to the
    ///      coach is the wrong action here — the user should reach a
    ///      human, not chat with the AI. The Done button on the parent
    ///      surface is the only forward affordance.
    ///
    /// `accessibilityLabel` carries the safety framing so screen-reader
    /// users hear "Support resources" before the body is read.
    private func safetyResourceCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header + body grouped into a single a11y element so
            // VoiceOver announces "Support resources, <body>" on first
            // focus. Link stays outside as a discrete focusable action.
            // Mirrors the ChatBubble safety variant for surface
            // consistency.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.coral)
                        .accessibilityHidden(true)
                    Text("Support resources")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.coral)
                }

                Text(message)
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            // Tappable hotline link — opens findahelpline.com (or the
            // region-specific URL `SafeResourceCopy.actionURL` returns)
            // in Safari. Pre-fix this was a plain-text URL inside the
            // body string, which VoiceOver and most users would not
            // recognize as actionable.
            Link(destination: SafeResourceCopy.actionURL()) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                    Text(SafeResourceCopy.findHelplineLabel())
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(AppColors.coral)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppColors.coral.opacity(0.1))
                .cornerRadius(AppRadius.sm)
                // Make the entire pill (including padding + background)
                // hit-testable. Without this, `Link`'s gesture region is
                // the rendered text bounds only and taps on the coral
                // padding miss. Same shape as the Reply button on the
                // recap card. BUG-05 from the safety-card QA pass.
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Find a helpline")
            .accessibilityHint("Opens findahelpline.com in your browser")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.coral.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.coral.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
    }

    private func generateRecap() async {
        guard let generator = recapGenerator else { return }
        isLoadingRecap = true
        let result = await generator.generate(
            currentTimeSlot: timeSlot,
            userName: userName,
            subscriptionTier: tier
        )
        // Discriminate via the typed result instead of string-equality
        // against `SafeResourceCopy.message()`. The previous string match
        // was fragile against any copy edit and against locale drift
        // between generator and view (BUG-01/02 from the safety-card
        // QA pass). Now the generator's return type carries the
        // safety-vs-insight intent explicitly.
        switch result {
        case .insight(let text):
            recapMessage = text
            isSafetyRecap = false
        case .safety(let text):
            recapMessage = text
            isSafetyRecap = true
        case .none:
            recapMessage = nil
            isSafetyRecap = false
        }
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

            // Continue is hidden on the single-select rating steps (mood,
            // energy) since the tap *is* the answer — auto-advance kicks
            // in after a 250ms beat. Greeting still needs an explicit
            // Begin tap (loading gate); notes needs an explicit Complete
            // (free-text has no natural commit moment). VoiceOver users
            // always see Continue (auto-advance disabled for them).
            //
            // We always render the Continue slot — invisible + non-hit
            // when hidden — so the footer geometry doesn't thrash on
            // step change (BUG-03 from the QA pass on this commit).
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
            .disabled(!canAdvance || !showsForwardButton)
            .opacity(showsForwardButton ? 1 : 0)
            .accessibilityHidden(!showsForwardButton)
            .animation(.easeInOut(duration: 0.2), value: showsForwardButton)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    /// Auto-advance steps suppress the forward button — but ONLY when
    /// auto-advance is active. Under VoiceOver we keep Continue visible
    /// so screen-reader users have an explicit, predictable advance
    /// affordance and don't lose focus mid-announcement.
    private var showsForwardButton: Bool {
        switch currentStep {
        case .greeting, .notes: return true
        case .mood, .energy:
            return UIAccessibility.isVoiceOverRunning
        case .complete: return false
        }
    }

    /// Schedule a 250ms beat then call `goForward`. The beat lets the
    /// selection state register visually so the tap doesn't feel
    /// stolen. Generation-fenced — cancellation is via incrementing
    /// `advanceGeneration`; the awaiting task only commits if its
    /// captured generation still matches. Skipped entirely under
    /// VoiceOver so screen-reader users get the explicit Continue
    /// affordance instead of having focus yanked mid-announcement.
    private func scheduleAutoAdvance() {
        // VoiceOver: skip auto-advance, surface Continue button instead.
        // `showsForwardButton` reads the same flag so they stay in sync.
        if UIAccessibility.isVoiceOverRunning { return }

        advanceGeneration += 1
        let myGen = advanceGeneration
        isAdvancing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            // Synchronous fence: only the most recently scheduled
            // generation may commit. A stale task that woke after
            // a re-schedule, dismiss, or back-nav drops here.
            guard myGen == advanceGeneration else { return }
            isAdvancing = false
            withAnimation(.easeInOut(duration: 0.3)) {
                goForward()
            }
        }
    }

    /// Invalidate any pending auto-advance — used by goBack, onDisappear,
    /// and finalize paths so a stale beat can't fire goForward against
    /// torn-down state.
    private func cancelPendingAdvance() {
        advanceGeneration += 1
        isAdvancing = false
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
        // Cancel any pending auto-advance — user changed direction.
        cancelPendingAdvance()
        switch currentStep {
        case .mood: currentStep = .greeting
        case .energy: currentStep = .mood
        case .notes: currentStep = .energy
        default: break
        }
    }

    private func loadGreeting() {
        // Hard timeout so a hung Claude call never strands the user on
        // the greeting screen. After 6 seconds we fall back to the
        // hardcoded slot greeting and unblock the Continue button.
        // Whichever completes first (the real greeting or the timeout)
        // flips isLoadingGreeting; the other becomes a no-op. The timeout
        // task is always cancelled on exit (including any future error
        // path from `generateGreeting`) so it can't leak past the view.
        Task {
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, isLoadingGreeting else { return }
                aiGreeting = timeSlot.greeting
                isLoadingGreeting = false
            }
            // Cancel even if the body below throws — stops the fallback
            // from jolting the user after a successful / explicit result.
            defer { timeoutTask.cancel() }

            if let manager = checkInManager {
                let greeting = await manager.generateGreeting(
                    timeSlot: timeSlot,
                    mood: nil,
                    keychain: keychainService,
                    tier: tier,
                    scheduleSummary: taskManager?.scheduleSummary() ?? "",
                    completionRate: patternEngine?.completionRate() ?? 0,
                    streak: patternEngine?.currentStreak() ?? 0
                )
                // Only apply if we beat the timeout — otherwise the
                // fallback has already been shown and we don't want to
                // jolt the user by swapping the copy mid-read.
                await MainActor.run {
                    guard isLoadingGreeting else { return }
                    aiGreeting = greeting
                    isLoadingGreeting = false
                }
            } else {
                await MainActor.run {
                    aiGreeting = timeSlot.greeting
                    isLoadingGreeting = false
                }
            }
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
