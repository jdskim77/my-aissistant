import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.insightEngine) private var insightEngine
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.wisdomManager) private var wisdomManager
    @Environment(\.balanceManager) private var balanceManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @Query(sort: \HabitItem.createdAt) private var allHabits: [HabitItem]
    @Query(filter: #Predicate<CheckInRecord> { $0.completed == true },
           sort: \CheckInRecord.date, order: .reverse) private var allCheckIns: [CheckInRecord]

    @State private var appeared = false
    @State private var showingCheckIn = false
    @State private var overdueExpanded = true
    @State private var completedExpanded = false
    @State private var tomorrowExpanded = false
    @State private var taskToReschedule: TaskItem?
    @State private var taskToDelete: TaskItem?
    @State private var showingHabits = false
    @State private var rescheduleDate = Date()
    @State private var greetingManager = GreetingManager()
    @State private var greetingOrbActive = false
    @State private var celebrationMilestone: Int?

    // MARK: - Computed

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Check-in State

    /// Slots completed today, deduped by slot (one record per slot per day).
    private var todayCompletedSlots: Set<String> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Set(allCheckIns.filter { $0.date >= startOfDay }.map(\.timeSlotRaw))
    }

    private var todayCheckInCount: Int { todayCompletedSlots.count }

    private func isSlotCompletedToday(_ slot: CheckInTime) -> Bool {
        todayCompletedSlots.contains(slot.rawValue)
    }

    private enum CheckInCardState {
        case prominent(slot: CheckInTime)
        case progress
        case complete
    }

    private var checkInCardState: CheckInCardState {
        if todayCheckInCount >= 4 { return .complete }
        // Show the prominent card whenever the slot the user is currently in
        // hasn't been logged yet. No artificial windowing — if it's that slot's
        // hours and the user hasn't checked in, they should see it.
        let current = CheckInTime.current()
        if !isSlotCompletedToday(current) {
            return .prominent(slot: current)
        }
        return .progress
    }

    private var formattedDate: String {
        Date().formatted(as: "EEEE, MMMM d")
    }

    private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var endOfToday: Date {
        Calendar.current.safeDate(byAdding: .day, value: 1, to: startOfToday)
    }

    private var overdueTasks: [TaskItem] {
        allTasks.filter { $0.date < startOfToday && !$0.done }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var todayActiveTasks: [TaskItem] {
        allTasks.filter { $0.date >= startOfToday && $0.date < endOfToday && !$0.done && $0.externalCalendarID == nil }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    private var todayCalendarEvents: [TaskItem] {
        allTasks.filter { $0.date >= startOfToday && $0.date < endOfToday && $0.externalCalendarID != nil && !$0.done }
            .sorted { $0.date < $1.date }
    }

    private var todayCompletedTasks: [TaskItem] {
        allTasks.filter { $0.date >= startOfToday && $0.date < endOfToday && $0.done }
    }

    private var totalTodayCount: Int {
        allTasks.filter { $0.date >= startOfToday && $0.date < endOfToday }.count
    }

    private var completedTodayCount: Int {
        todayCompletedTasks.count
    }

    private var streak: Int {
        patternEngine?.currentStreak() ?? 0
    }

    private var completionFraction: Double {
        guard totalTodayCount > 0 else { return 0 }
        return Double(completedTodayCount) / Double(totalTodayCount)
    }

    private var startOfTomorrow: Date { endOfToday }

    private var endOfTomorrow: Date {
        Calendar.current.safeDate(byAdding: .day, value: 2, to: startOfToday)
    }

    private var activeHabits: [HabitItem] {
        allHabits.filter { !$0.isArchived }
    }

    private var tomorrowTasks: [TaskItem] {
        allTasks.filter { $0.date >= startOfTomorrow && $0.date < endOfTomorrow && !$0.done }
            .sorted { $0.priority.sortOrder < $1.priority.sortOrder }
    }

    // MARK: - Body

    var body: some View {
        List {
            // AI Greeting
            if greetingManager.isShowingGreeting {
                Section {
                    AIGreetingCard(
                        greeting: greetingManager.currentGreeting,
                        isAnimating: greetingOrbActive,
                        onDismiss: { greetingManager.dismissGreeting() }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // Compact header
            Section {
                headerView
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Daily wisdom (70/20/10 intelligent selection)
            if let quote = wisdomManager?.todayQuote(
                compassScores: balanceManager?.weeklyScores().reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
                currentMood: nil,
                streak: streak
            ) ?? WisdomManager.todayQuote() {
                Section {
                    wisdomCard(quote: quote)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // Today hero card (tasks + check-ins + streak + contextual action)
            Section {
                todayHeroCard
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Micro-insight
            if let insight = insightEngine?.todayInsight() {
                Section {
                    insightCard(insight)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // Habits section
            if !activeHabits.isEmpty {
                Section {
                    habitsCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Button {
                        showingHabits = true
                    } label: {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.accent)
                            Text("Habits")
                                .font(AppFonts.heading(15))
                                .foregroundColor(AppColors.textPrimary)
                                .textCase(nil)
                            Spacer()
                            Text("See all")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.accent)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                    .buttonStyle(.scale)
                }
            }

            // Overdue section
            if !overdueTasks.isEmpty {
                Section {
                    if overdueExpanded {
                        ForEach(overdueTasks, id: \.id) { task in
                            TaskCard(task: task, isOverdue: true) {
                                Haptics.success()
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Haptics.medium()
                                    taskToDelete = task
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    Haptics.light()
                                    taskToReschedule = task
                                    rescheduleDate = Date()
                                } label: {
                                    Label("Reschedule", systemImage: "calendar.badge.clock")
                                }
                                .tint(AppColors.skyBlue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    Haptics.success()
                                    withAnimation(.spring(response: 0.3)) {
                                        taskManager?.toggleCompletion(task)
                                    }
                                } label: {
                                    Label("Complete", systemImage: "checkmark.circle.fill")
                                }
                                .tint(AppColors.completionGreen)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                } header: {
                    collapsibleHeader(
                        title: "Overdue",
                        count: overdueTasks.count,
                        isExpanded: $overdueExpanded,
                        tintColor: AppColors.overdueRed
                    )
                }
            }

            // Today section
            Section {
                // Calendar events inline
                ForEach(todayCalendarEvents, id: \.id) { event in
                    CalendarEventRow(task: event) {
                        Haptics.success()
                        withAnimation(.spring(response: 0.3)) {
                            taskManager?.toggleCompletion(event)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            withAnimation {
                                Task { await calendarSyncManager?.deleteCalendarEvent(for: event) }
                                taskManager?.deleteTask(event)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Haptics.success()
                            withAnimation(.spring(response: 0.3)) {
                                taskManager?.toggleCompletion(event)
                            }
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(AppColors.completionGreen)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }

                // Active tasks
                if todayActiveTasks.isEmpty && todayCalendarEvents.isEmpty && overdueTasks.isEmpty {
                    emptyActiveState
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                } else {
                    ForEach(todayActiveTasks, id: \.id) { task in
                        TaskCard(task: task) {
                            Haptics.success()
                            withAnimation(.spring(response: 0.3)) {
                                taskManager?.toggleCompletion(task)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Haptics.heavy()
                                withAnimation {
                                    if task.externalCalendarID != nil {
                                        Task { await calendarSyncManager?.deleteCalendarEvent(for: task) }
                                    }
                                    taskManager?.deleteTask(task)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Haptics.light()
                                taskToReschedule = task
                                rescheduleDate = Date()
                            } label: {
                                Label("Reschedule", systemImage: "calendar.badge.clock")
                            }
                            .tint(AppColors.skyBlue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                Haptics.success()
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(AppColors.completionGreen)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
            } header: {
                Text("Today")
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
                    .textCase(nil)
            }

            // All done celebration
            if !todayActiveTasks.isEmpty || completedTodayCount == 0 {
                // Don't show celebration
            } else if todayActiveTasks.isEmpty && completedTodayCount > 0 && overdueTasks.isEmpty {
                Section {
                    allDoneState
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                }
            }

            // Completed section
            if !todayCompletedTasks.isEmpty {
                Section {
                    if completedExpanded {
                        ForEach(todayCompletedTasks, id: \.id) { task in
                            TaskCard(task: task) {
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        if task.externalCalendarID != nil {
                                            Task { await calendarSyncManager?.deleteCalendarEvent(for: task) }
                                        }
                                        taskManager?.deleteTask(task)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        taskManager?.toggleCompletion(task)
                                    }
                                } label: {
                                    Label("Undo", systemImage: "arrow.uturn.backward")
                                }
                                .tint(AppColors.accentWarm)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .opacity(0.6)
                        }
                    }
                } header: {
                    collapsibleHeader(
                        title: "Completed",
                        count: todayCompletedTasks.count,
                        isExpanded: $completedExpanded,
                        tintColor: AppColors.completionGreen
                    )
                }
            }

            // Tomorrow section
            if !tomorrowTasks.isEmpty {
                Section {
                    if tomorrowExpanded {
                        ForEach(tomorrowTasks, id: \.id) { task in
                            TaskCard(task: task) {
                                withAnimation(.spring(response: 0.3)) {
                                    taskManager?.toggleCompletion(task)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        if task.externalCalendarID != nil {
                                            Task { await calendarSyncManager?.deleteCalendarEvent(for: task) }
                                        }
                                        taskManager?.deleteTask(task)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    taskToReschedule = task
                                    rescheduleDate = Date()
                                } label: {
                                    Label("Reschedule", systemImage: "calendar.badge.clock")
                                }
                                .tint(AppColors.skyBlue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        taskManager?.toggleCompletion(task)
                                    }
                                } label: {
                                    Label("Complete", systemImage: "checkmark.circle.fill")
                                }
                                .tint(AppColors.completionGreen)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                } header: {
                    collapsibleHeader(
                        title: "Tomorrow",
                        count: tomorrowTasks.count,
                        isExpanded: $tomorrowExpanded,
                        tintColor: AppColors.skyBlue
                    )
                }
            }

            // Bottom spacer so the last section can scroll above the tab bar
            Section {
                Color.clear
                    .frame(height: 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .overlay {
            if let milestone = celebrationMilestone {
                CelebrationView(milestone: milestone) {
                    StreakMilestone.markCelebrated(streak: milestone)
                    celebrationMilestone = nil
                }
            }
        }
        .onAppear {
            // Check for streak milestone celebration
            let currentStreak = patternEngine?.currentStreak() ?? 0
            // Reset celebration tracking when streak breaks so milestones can re-trigger
            if currentStreak == 0 {
                StreakMilestone.resetCelebrations()
            }
            if StreakMilestone.shouldCelebrate(streak: currentStreak) {
                celebrationMilestone = currentStreak
            }
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }

            // Generate contextual AI greeting
            let todayTasks = taskManager?.todayTasks() ?? []
            let highPriority = taskManager?.highPriorityUpcoming(limit: 1) ?? []
            let isNew = greetingManager.generateGreetingIfNeeded(
                todayTaskCount: todayTasks.count,
                completedTodayCount: todayTasks.filter(\.done).count,
                highPriorityTitles: highPriority.map(\.title),
                completionRate: patternEngine?.completionRate() ?? 0,
                streak: patternEngine?.currentStreak() ?? 0
            )

            // Pulse the orb briefly on fresh greetings
            if isNew {
                greetingOrbActive = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    await MainActor.run { greetingOrbActive = false }
                }
            }

            // Auto-dismiss greeting after 30 seconds
            Task {
                try? await Task.sleep(for: .seconds(30))
                await MainActor.run { greetingManager.dismissGreeting() }
            }
        }
        .sheet(isPresented: $showingCheckIn) {
            CheckInDetailView(timeSlot: CheckInTime.next())
        }
        .sheet(isPresented: $showingHabits) {
            HabitsView()
        }
        .sheet(item: $taskToReschedule) { task in
            rescheduleSheet(for: task)
        }
        .alert("Delete Task", isPresented: Binding(
            get: { taskToDelete != nil },
            set: { if !$0 { taskToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let task = taskToDelete else { return }
                Haptics.heavy()
                withAnimation {
                    if task.externalCalendarID != nil {
                        Task { await calendarSyncManager?.deleteCalendarEvent(for: task) }
                    }
                    taskManager?.deleteTask(task)
                }
                taskToDelete = nil
            }
            Button("Cancel", role: .cancel) { taskToDelete = nil }
        } message: {
            Text("Are you sure you want to delete \"\(taskToDelete?.title ?? "")\"?")
        }
    }

    // MARK: - Daily Wisdom Card

    /// Editorial blockquote with a soft warm tint. The original "no chrome"
    /// design was too restrained against the surrounding cards — it read as
    /// whitespace, not content. The tint gives it a "different content type"
    /// container without competing for attention with the functional cards
    /// (Today Hero, Pattern Insight) above and below it.
    /// Theme-safe: uses semantic AppColors that adapt across all color schemes.
    private func wisdomCard(quote: WisdomManager.Quote) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Vertical accent bar — bumped from 3pt to 4pt so it registers as
            // a structural element instead of a divider line.
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.accentWarm)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("\u{201C}\(quote.text)\u{201D}")
                    .font(AppFonts.display(17))
                    .foregroundColor(AppColors.textPrimary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                Text("\u{2014} \(quote.author)")
                    .font(AppFonts.bodyMedium(12))
                    .foregroundColor(AppColors.textSecondary)
                    .tracking(0.3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.accentWarm.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentWarm.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily wisdom: \(quote.text), by \(quote.author)")
    }

    // MARK: - Today Hero Card
    //
    // Single source of truth for "today's progress + today's action".
    // Replaces the old separate stats card and prominent check-in card.
    // Adaptive bottom slot will absorb future actions (goal task, season plan, etc.).

    /// Blended day completion: tasks + check-ins as a single 0..1 fraction.
    /// Apple Fitness pattern — one number that captures "how much of today did I do".
    private var dayCompletionFraction: Double {
        let totalUnits = totalTodayCount + 4
        guard totalUnits > 0 else { return 0 }
        let doneUnits = completedTodayCount + todayCheckInCount
        return min(1.0, Double(doneUnits) / Double(totalUnits))
    }

    private var todayHeroCard: some View {
        VStack(spacing: 12) {
            // Top: header strip (TODAY + streak only — date already in greeting above)
            HStack {
                Text("TODAY")
                    .font(AppFonts.label(11))
                    .tracking(0.8)
                    .foregroundColor(AppColors.textMuted)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 3) {
                        Text("\(streak)")
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(AppColors.accentWarm)
                        Text("🔥").font(.system(size: 13))
                    }
                }
            }

            // Hero ring — single iconic focal point (smaller, confident)
            ZStack {
                Circle()
                    .stroke(AppColors.border, lineWidth: 7)
                    .frame(width: 108, height: 108)
                Circle()
                    .trim(from: 0, to: max(0, min(1, dayCompletionFraction)))
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 108, height: 108)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(dayCompletionFraction * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.textPrimary)
                        .monospacedDigit()
                    Text(dayCompletionFraction >= 1 ? "all done" : "of day done")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today: \(Int(dayCompletionFraction * 100)) percent done. \(completedTodayCount) of \(totalTodayCount) tasks, \(todayCheckInCount) of 4 check-ins.")

            // Breakdown row — symmetric two halves with center divider
            HStack(spacing: 0) {
                heroBreakdownStat(
                    label: "Tasks",
                    value: "\(completedTodayCount)/\(totalTodayCount)",
                    color: AppColors.completionGreen
                )
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 1, height: 28)

                heroBreakdownStat(
                    label: "Check-ins",
                    value: "\(todayCheckInCount)/4",
                    color: AppColors.accent
                )
                .frame(maxWidth: .infinity)
            }

            // Slot icons row — centered below both halves so neither side feels heavier
            HStack(spacing: 8) {
                ForEach(CheckInTime.allCases) { slot in
                    Image(systemName: slot.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSlotCompletedToday(slot) ? slot.color : AppColors.border)
                }
            }

            if !overdueTasks.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.overdueRed)
                    Text("\(overdueTasks.count) overdue")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.overdueRed)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }

            // Action slot — only renders in .prominent / .complete states.
            // In .progress (between slots) the card stops here for a cleaner look.
            if case .progress = checkInCardState {
                EmptyView()
            } else {
                heroActionRow
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColors.card)
                .overlay(
                    // Subtle radial gradient for premium feel
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            RadialGradient(
                                colors: [AppColors.accent.opacity(0.05), Color.clear],
                                center: .top,
                                startRadius: 10,
                                endRadius: 220
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        )
        .offset(y: appeared ? 0 : 15)
        .opacity(appeared ? 1 : 0)
    }

    /// One half of the breakdown row under the hero ring: small color dot + label + count.
    private func heroBreakdownStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label.uppercased())
                    .font(AppFonts.label(10))
                    .tracking(0.6)
                    .foregroundColor(AppColors.textMuted)
            }
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
                .monospacedDigit()
        }
    }

    /// Adaptive bottom slot: shows whichever action is most relevant.
    /// Today this is "current check-in needed" or "day complete".
    /// Future Phases will plug in goal tasks and season plan progress here.
    @ViewBuilder
    private var heroActionRow: some View {
        switch checkInCardState {
        case .prominent(let slot):
            Button { showingCheckIn = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: slot.sfSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(slot.color)
                        .frame(width: 28, height: 28)
                        .background(slot.color.opacity(0.15))
                        .clipShape(Circle())
                    Text("\(slot.rawValue) check-in")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(slot.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(slot.color.opacity(0.08))
                )
            }
            .buttonStyle(.scale)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(slot.rawValue) check-in available. \(todayCheckInCount) of 4 done today. Tap to start.")
        case .complete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.completionGreen)
                Text("All check-ins done — see you tomorrow")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.completionGreen)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        case .progress:
            // Between active windows — no urgent action.
            // Tap target so users can still log a backfill check-in.
            Button { showingCheckIn = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.accent)
                    Text("Add a check-in")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Insight Card

    private func insightCard(_ insight: InsightEngine.Insight) -> some View {
        HStack(spacing: 12) {
            Image(systemName: insight.icon)
                .font(AppFonts.heading(20))
                .foregroundColor(AppColors.accent)
                .frame(width: 36, height: 36)
                .background(AppColors.accent.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Pattern Insight")
                    .font(AppFonts.label(11))
                    .foregroundColor(AppColors.accent)
                Text(insight.text)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.accent.opacity(0.15), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pattern insight: \(insight.text)")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)
                Text(formattedDate)
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Header chip removed — Today hero card surfaces all check-in info now.
            EmptyView()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(y: appeared ? 0 : 15)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Collapsible Section Header

    private func collapsibleHeader(title: String, count: Int, isExpanded: Binding<Bool>, tintColor: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Image(systemName: title == "Overdue" ? "exclamationmark.triangle.fill" : title == "Tomorrow" ? "sunrise.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(tintColor)
                Text("\(title) (\(count))")
                    .font(AppFonts.heading(15))
                    .foregroundColor(AppColors.textPrimary)
                    .textCase(nil)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textMuted)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
        }
        .buttonStyle(.scale)
    }

    // MARK: - Empty States

    private var emptyActiveState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max")
                .font(.system(size: 40))
                .foregroundColor(AppColors.accentWarm)
            Text("No tasks today")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text("Head to Schedule to add tasks")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var allDoneState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.completionGreen)
            Text("All done for today!")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text("You completed \(completedTodayCount) task\(completedTodayCount == 1 ? "" : "s")")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Habits Card

    private var habitsCard: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let doneCount = activeHabits.filter { $0.isCompletedOn(today) }.count

        return VStack(spacing: 10) {
            ForEach(activeHabits.prefix(4)) { habit in
                let isDone = habit.isCompletedOn(today)
                HStack(spacing: 10) {
                    Button {
                        Haptics.success()
                        withAnimation(.spring(response: 0.3)) {
                            habit.toggleCompletion(for: today)
                            try? modelContext.save()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(isDone ? AppColors.completionGreen : Color(hex: habit.colorHex), lineWidth: 2)
                                .frame(width: 22, height: 22)
                            if isDone {
                                Circle()
                                    .fill(AppColors.completionGreen)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(habit.icon)
                        .font(.system(size: 16))
                    Text(habit.title)
                        .font(AppFonts.body(14))
                        .foregroundColor(isDone ? AppColors.textMuted : AppColors.textPrimary)
                        .strikethrough(isDone)
                    Spacer()

                    let streak = habit.currentStreak()
                    if streak > 0 {
                        Text("\(streak)🔥")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.accentWarm)
                    }
                }
            }

            if activeHabits.count > 4 {
                Button {
                    showingHabits = true
                } label: {
                    Text("+\(activeHabits.count - 4) more")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        )
    }

    // MARK: - Reschedule Sheet

    private func rescheduleSheet(for task: TaskItem) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Reschedule \"\(task.title)\"")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                // Quick buttons
                HStack(spacing: 12) {
                    quickRescheduleButton("Tomorrow", daysFromNow: 1, task: task)
                    quickRescheduleButton("In 3 days", daysFromNow: 3, task: task)
                    quickRescheduleButton("Next week", daysFromNow: 7, task: task)
                }

                Divider()

                // Date picker
                DatePicker("Pick a date", selection: $rescheduleDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(AppColors.accent)

                Button {
                    taskManager?.rescheduleTask(task, to: rescheduleDate)
                    taskToReschedule = nil
                } label: {
                    Text("Reschedule")
                        .font(AppFonts.bodyMedium(16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent)
                        .cornerRadius(12)
                }
                .buttonStyle(.scale)

                Spacer()
            }
            .padding(.horizontal, 20)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { taskToReschedule = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func quickRescheduleButton(_ label: String, daysFromNow: Int, task: TaskItem) -> some View {
        Button {
            let target = Calendar.current.safeDate(byAdding: .day, value: daysFromNow, to: Date())
            taskManager?.rescheduleTask(task, to: target)
            taskToReschedule = nil
        } label: {
            Text(label)
                .font(AppFonts.label(13))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppColors.accentLight)
                .cornerRadius(10)
        }
        .buttonStyle(.scale)
    }
}
