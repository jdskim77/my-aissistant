import SwiftUI
import SwiftData

struct HabitsView: View {
    @Environment(\.habitManager) private var habitManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HabitItem.createdAt) private var allHabits: [HabitItem]
    @State private var showingAddHabit = false
    @State private var habitToEdit: HabitItem?
    @State private var missedSectionExpanded = false
    @State private var lastMissed: LastMissed?
    @State private var undoDismissTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let calendar = Calendar.current

    private var activeHabits: [HabitItem] {
        allHabits.filter { !$0.isArchived }
    }

    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    /// Habits visible in the main Today list — everything except explicitly
    /// missed habits, which live in a separate collapsed group below.
    private var todayVisibleHabits: [HabitItem] {
        activeHabits.filter { !$0.isMissedOn(today) }
    }

    /// Habits marked missed AND still scheduled for today. If a habit's
    /// `targetDays` is edited after being marked missed, it should no longer
    /// show a "missed today" badge on a day it's not scheduled for.
    private var missedTodayHabits: [HabitItem] {
        activeHabits.filter { $0.isMissedOn(today) && $0.targetDays.appliesTo(date: today) }
    }

    /// Last 7 days for the grid header
    private var weekDates: [Date] {
        (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 20) {
                        if activeHabits.isEmpty {
                            emptyState
                        } else {
                            todaySection

                            if !missedTodayHabits.isEmpty {
                                missedSection
                            }

                            weeklyGrid
                            statsSection
                        }
                    }
                    .padding(.bottom, 100)
                }
                .background(AppColors.background.ignoresSafeArea())

                if let last = lastMissed {
                    undoToast(for: last)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.light()
                        showingAddHabit = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFonts.heading(22))
                            .foregroundColor(AppColors.accent)
                    }
                    .accessibilityLabel("Add new habit")
                }
            }
            .sheet(isPresented: $showingAddHabit) {
                HabitFormView(mode: .create)
            }
            .sheet(item: $habitToEdit) { habit in
                HabitFormView(mode: .edit(habit))
            }
            // Pause the toast's auto-dismiss while an edit sheet is up (toast
            // is hidden behind it) or while the user is on another tab —
            // then reset a fresh 5 s window when they return, so the undo
            // opportunity isn't lost to out-of-view time.
            .onChange(of: habitToEdit) { _, newValue in
                if newValue != nil {
                    cancelUndoTimer()
                } else if lastMissed != nil {
                    startUndoTimer()
                }
            }
            .onDisappear {
                cancelUndoTimer()
            }
            .onAppear {
                if lastMissed != nil, undoDismissTask == nil {
                    startUndoTimer()
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: "leaf.fill")
                .font(AppFonts.icon(44))
                .foregroundColor(AppColors.textMuted)
            Text("No habits yet")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text("Build consistency by tracking daily habits")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
            Button {
                Haptics.light()
                showingAddHabit = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add First Habit")
                }
                .font(AppFonts.bodyMedium(15))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .cornerRadius(14)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Today Section

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                // Denominator = habits scheduled for today (includes missed so
                // the day's expected load stays honest); numerator = completed.
                let applicableToday = activeHabits.filter { $0.targetDays.appliesTo(date: today) }
                let done = applicableToday.filter { $0.isCompletedOn(today) }.count
                Text("\(done)/\(applicableToday.count)")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 20)

            // `TimelineView(.explicit(...))` fires only at window
            // boundary crossings (hours 2, 6, 11, 16, 20 relative to
            // local midnight). Unlike `.periodic(by: 60)`, it doesn't
            // re-run the streak-by-sort comparator every minute —
            // that was O(n·90) work per tick for a 15-habit user
            // (BUG-03 fix).
            TimelineView(.explicit(Self.windowBoundaryDates(from: Date()))) { timeline in
                let now = timeline.date
                VStack(spacing: 0) {
                    ForEach(sortedForDisplay(todayVisibleHabits, at: now)) { habit in
                        let isDone = habit.isCompletedOn(today)
                        let appliesToday = habit.targetDays.appliesTo(date: today)
                        let canMiss = !isDone && appliesToday
                        let state = habit.windowState(at: now)
                        SwipeToMissRow(
                            enabled: canMiss,
                            reduceMotion: reduceMotion,
                            onCommit: { commitMiss(habit) }
                        ) {
                            habitRowWithActions(habit, canMiss: canMiss)
                        }
                        // `.opacity` applied on the wrapping SwipeToMissRow
                        // so the coral "Miss" reveal layer dims too — not
                        // just the habit row foreground (BUG-10 fix).
                        // 0.6 (up from 0.5) clears WCAG 2.2 AA 3:1 UI-
                        // component contrast against cream (BUG-06 part).
                        .opacity(state == .outOfWindow ? 0.6 : 1.0)
                        .accessibilityLabel(accessibilityLabel(for: habit, state: state))
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    /// Unified sort with time-window awareness, matching HomeView's
    /// policy so the two surfaces show habits in the same order:
    /// 1. In-window / all-day habits first
    /// 2. Out-of-window habits last
    /// Tiebreak inside each band: streak desc (long-streak habits
    /// surface first), then `createdAt` ascending for stable ordering
    /// across TimelineView ticks (BUG-07, BUG-08 fix).
    private func sortedForDisplay(_ habits: [HabitItem], at now: Date) -> [HabitItem] {
        habits.sorted { lhs, rhs in
            let lDim = lhs.windowState(at: now) == .outOfWindow ? 1 : 0
            let rDim = rhs.windowState(at: now) == .outOfWindow ? 1 : 0
            if lDim != rDim { return lDim < rDim }
            let lStreak = lhs.currentStreak()
            let rStreak = rhs.currentStreak()
            if lStreak != rStreak { return lStreak > rStreak }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// VoiceOver label composed from the habit's state so screen-reader
    /// users get the window info that sighted users see via opacity
    /// (BUG-06 a11y part — opacity alone is color-only per ui-ux.md §2.5).
    private func accessibilityLabel(for habit: HabitItem, state: HabitWindowState) -> String {
        var label = habit.title
        if state == .outOfWindow, let window = habit.timeWindow {
            label += ", \(window.label) habit, outside its window"
        }
        return label
    }

    /// Boundary dates for the next ~48 hours that TimelineView should
    /// fire on. Hours 2, 6, 11, 16, 20 — one per window transition +
    /// the post-midnight night-window edge. Fires at most 10 times per
    /// day instead of 1440 with `.periodic(by: 60)`.
    private static func windowBoundaryDates(from reference: Date,
                                             calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: reference)
        let hours = [2, 6, 11, 16, 20]
        var dates: [Date] = []
        for dayOffset in 0...1 {
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }
            for hour in hours {
                if let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart),
                   d > reference {
                    dates.append(d)
                }
            }
        }
        return dates.sorted()
    }

    /// Wraps `habitRow` with a VoiceOver custom action so the swipe-to-miss
    /// gesture has a non-gestural equivalent. Screen reader users get
    /// "Mark as missed today" in the rotor actions list.
    @ViewBuilder
    private func habitRowWithActions(_ habit: HabitItem, canMiss: Bool) -> some View {
        if canMiss {
            habitRow(habit)
                .accessibilityAction(named: Text("Mark as missed today")) {
                    commitMiss(habit)
                }
        } else {
            habitRow(habit)
        }
    }

    private func habitRow(_ habit: HabitItem) -> some View {
        let isDone = habit.isCompletedOn(today)
        let streak = habit.currentStreak()

        return HStack(spacing: 14) {
            // Checkbox
            Button {
                let wasDone = habit.isCompletedOn(today)
                withAnimation(reduceMotion ? .none : .spring(response: 0.3)) {
                    habitManager?.toggleCompletion(habit, for: today)
                }
                // Only fire the haptic when the toggle actually mutated
                // state. HabitManager throttles rapid taps (0.25 s window);
                // without this guard a throttled tap still buzzed, lying
                // about whether the tap landed.
                if habit.isCompletedOn(today) != wasDone {
                    Haptics.success()
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(isDone ? AppColors.completionGreen : habit.effectiveColor, lineWidth: 2.5)
                        .frame(width: 28, height: 28)
                    if isDone {
                        Circle()
                            .fill(AppColors.completionGreen)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(AppFonts.label(13))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.title), \(isDone ? "completed" : "not completed")")
            .accessibilityHint(isDone ? "Double tap to mark as not completed" : "Double tap to mark as completed")
            .accessibilityAddTraits(.isButton)

            Text(habit.icon)
                .font(AppFonts.heading(22))

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(isDone ? AppColors.textMuted : AppColors.textPrimary)
                    .strikethrough(isDone)

                if streak > 0 {
                    Text("\(streak) day streak 🔥")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.accentWarm)
                }
            }

            Spacer()

            habitActionsMenu(habit, isDone: isDone)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(AppColors.background)
    }

    private func habitActionsMenu(_ habit: HabitItem, isDone: Bool) -> some View {
        let appliesToday = habit.targetDays.appliesTo(date: today)
        return Menu {
            if !isDone && appliesToday {
                Button {
                    Haptics.warning()
                    commitMiss(habit)
                } label: {
                    Label("Mark as missed today", systemImage: "xmark.circle")
                }
            }
            Button {
                Haptics.light()
                habitToEdit = habit
            } label: {
                Label("Edit habit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                Haptics.medium()
                dismissToastIfReferencing(habit.id)
                habitManager?.archive(habit)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(AppFonts.body(14).weight(.medium))
                .foregroundColor(AppColors.textMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options for \(habit.title)")
    }

    // MARK: - Missed Section

    private var missedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
                    missedSectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(AppFonts.label(11))
                        .foregroundColor(AppColors.textMuted)
                        .rotationEffect(.degrees(missedSectionExpanded ? 90 : 0))
                    Text("Missed today")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.textMuted)
                    Text("\(missedTodayHabits.count)")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.border.opacity(0.6)))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Missed today, \(missedTodayHabits.count) \(missedTodayHabits.count == 1 ? "habit" : "habits")")
            .accessibilityHint(missedSectionExpanded ? "Double tap to collapse" : "Double tap to expand")

            if missedSectionExpanded {
                ForEach(missedTodayHabits) { habit in
                    missedHabitRow(habit)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func missedHabitRow(_ habit: HabitItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AppColors.textMuted.opacity(0.4), lineWidth: 2)
                    .frame(width: 24, height: 24)
                Rectangle()
                    .fill(AppColors.textMuted.opacity(0.7))
                    .frame(width: 8, height: 2)
            }
            .frame(width: 44, height: 40)
            .accessibilityHidden(true)

            Text(habit.icon)
                .font(AppFonts.body(16))
                .opacity(0.55)

            Text(habit.title)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
                .strikethrough(color: AppColors.textMuted.opacity(0.6))

            Spacer()

            Text("Missed")
                .font(AppFonts.caption(10))
                .foregroundColor(AppColors.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().stroke(AppColors.border, lineWidth: 1))

            Menu {
                Button {
                    Haptics.light()
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
                        habitManager?.unmarkMissed(habit, for: today)
                    }
                } label: {
                    Label("Unmark missed", systemImage: "arrow.uturn.backward")
                }
                Button {
                    Haptics.light()
                    habitToEdit = habit
                } label: {
                    Label("Edit habit", systemImage: "pencil")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFonts.body(14).weight(.medium))
                    .foregroundColor(AppColors.textMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(habit.title)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(habit.title), missed today")
        .accessibilityAction(named: Text("Unmark missed")) {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.22)) {
                habitManager?.unmarkMissed(habit, for: today)
            }
        }
    }

    // MARK: - Miss / Undo flow

    private struct LastMissed: Equatable {
        let habitID: String
        let title: String
        /// The day the miss was committed for. Captured at commit time so
        /// tapping Undo after a day-boundary crossing unmarks the correct
        /// date rather than the current `today`.
        let date: Date
    }

    private func commitMiss(_ habit: HabitItem) {
        // Cancel the prior dismiss task BEFORE mutating state so its delayed
        // `lastMissed = nil` can't clobber the new toast.
        cancelUndoTimer()
        let committedDate = today
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
            habitManager?.markMissed(habit, for: committedDate)
            lastMissed = LastMissed(habitID: habit.id, title: habit.title, date: committedDate)
        }
        startUndoTimer()
    }

    /// Start (or restart) the 5 s auto-dismiss timer for the undo toast.
    /// Extracted so the timer can be paused while the user is on another
    /// tab or in a modal sheet — without those pauses, the toast silently
    /// expires out-of-view and the user loses the chance to undo.
    private func startUndoTimer() {
        cancelUndoTimer()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                lastMissed = nil
            }
        }
    }

    private func cancelUndoTimer() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
    }

    private func undoLastMiss() {
        guard let last = lastMissed else { return }
        cancelUndoTimer()
        // Unmark the day the miss was committed on, not "today" — they can
        // differ when the app was open across midnight. If the habit was
        // archived or deleted meanwhile, the toast still dismisses so the
        // Undo button isn't a silent no-op.
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
            if let habit = habitManager?.findHabit(byID: last.habitID) {
                habitManager?.unmarkMissed(habit, for: last.date)
            }
            lastMissed = nil
        }
    }

    /// Dismiss any undo toast that references the given habit. Called when a
    /// habit is archived/deleted so Undo isn't left pointing at a gone target.
    private func dismissToastIfReferencing(_ habitID: String) {
        guard lastMissed?.habitID == habitID else { return }
        cancelUndoTimer()
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.2)) {
            lastMissed = nil
        }
    }

    private func undoToast(for last: LastMissed) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(AppFonts.body(18))
                .foregroundColor(AppColors.coral)
            Text("Marked \u{201C}\(last.title)\u{201D} as missed")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 8)
            Button {
                Haptics.light()
                undoLastMiss()
            } label: {
                Text("Undo")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            // Keep the Undo button at its natural width regardless of how
            // long the habit title is — title truncates, Undo stays tappable.
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityLabel("Undo marking \(last.title) as missed")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    // MARK: - Weekly Grid

    private var weeklyGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                // Day headers
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 100)
                    ForEach(weekDates, id: \.self) { date in
                        VStack(spacing: 2) {
                            Text(date.formatted(as: "EEE"))
                                .font(AppFonts.label(10))
                                .foregroundColor(calendar.isDateInToday(date) ? AppColors.accent : AppColors.textMuted)
                            Text(date.formatted(as: "d"))
                                .font(AppFonts.caption(12))
                                .foregroundColor(calendar.isDateInToday(date) ? AppColors.accent : AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)

                // Habit rows
                ForEach(activeHabits) { habit in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Text(habit.icon)
                                .font(AppFonts.body(14))
                            Text(habit.title)
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 100, alignment: .leading)

                        ForEach(weekDates, id: \.self) { date in
                            let done = habit.isCompletedOn(date)
                            let missed = habit.isMissedOn(date)
                            let applies = habit.targetDays.appliesTo(date: date)
                            let dayName = date.formatted(as: "EEEE")
                            let stateLabel: String = {
                                guard applies else { return "not scheduled" }
                                if done { return "completed" }
                                if missed { return "missed" }
                                return "not completed"
                            }()
                            let isToday = calendar.isDateInToday(date)
                            ZStack {
                                if applies {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(done ? habit.effectiveColor : (missed ? AppColors.overdueBg : AppColors.border.opacity(0.5)))
                                        .frame(width: 24, height: 24)
                                    if done {
                                        Image(systemName: "checkmark")
                                            .font(AppFonts.label(11))
                                            .foregroundColor(.white)
                                    } else if missed {
                                        Image(systemName: "xmark")
                                            .font(AppFonts.label(10))
                                            .foregroundColor(AppColors.overdueRed)
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(AppColors.background)
                                        .frame(width: 24, height: 24)
                                }
                                // Today indicator: ring overlay so the current
                                // day is identifiable regardless of whether
                                // it's done, missed, pending, or off-day.
                                if isToday {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(AppColors.accent, lineWidth: 1.5)
                                        .frame(width: 24, height: 24)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(dayName)\(isToday ? " (today)" : ""), \(stateLabel)")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                ForEach(activeHabits) { habit in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(habit.icon)
                                .font(AppFonts.body(16))
                            Text(habit.title)
                                .font(AppFonts.bodyMedium(13))
                                .foregroundColor(AppColors.textPrimary)
                                .lineLimit(1)
                        }

                        let rate = habit.completionRate(days: 30)
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(habit.effectiveColor)
                                .frame(width: max(4, CGFloat(rate) * 100), height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppColors.border)
                                .frame(height: 6)
                        }
                        .cornerRadius(3)

                        HStack {
                            Text("\(Int(rate * 100))%")
                                .font(AppFonts.label(12))
                                .foregroundColor(habit.effectiveColor)
                            Spacer()
                            Text("\(habit.currentStreak())d streak")
                                .font(AppFonts.caption(11))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                    .padding(14)
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Swipe-to-miss row

/// Wraps a habit row with a left-swipe gesture that reveals a coral "Miss"
/// affordance and commits on threshold cross. Vertical drags are ignored so
/// the parent `ScrollView` still handles scroll naturally.
private struct SwipeToMissRow<Content: View>: View {
    let enabled: Bool
    let reduceMotion: Bool
    let onCommit: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var didTriggerCommitHaptic = false

    private let commitThreshold: CGFloat = 90
    private let maxReveal: CGFloat = 120

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFonts.body(18))
                    Text("Miss")
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(.white)
                .frame(width: maxReveal)
                .frame(maxHeight: .infinity)
                .background(AppColors.coral)
                .opacity(Double(min(1, -offset / commitThreshold)))
                .accessibilityHidden(true)
            }

            content()
                .contentShape(Rectangle())
                .offset(x: offset)
                .gesture(swipeGesture)
        }
        .clipped()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .onChanged { value in
                guard enabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // Only hijack when horizontal intent clearly dominates, so
                // vertical scrolling stays with the parent ScrollView.
                guard abs(dx) > abs(dy), dx < 0 else {
                    if offset != 0 {
                        withAnimation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.85)) {
                            offset = 0
                        }
                    }
                    return
                }
                offset = max(-maxReveal, dx)
                if offset <= -commitThreshold, !didTriggerCommitHaptic {
                    Haptics.selection()
                    didTriggerCommitHaptic = true
                } else if offset > -commitThreshold {
                    didTriggerCommitHaptic = false
                }
            }
            .onEnded { value in
                defer {
                    didTriggerCommitHaptic = false
                }
                guard enabled else {
                    withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.85)) {
                        offset = 0
                    }
                    return
                }
                if value.translation.width < -commitThreshold {
                    onCommit()
                }
                withAnimation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.85)) {
                    offset = 0
                }
            }
    }
}
