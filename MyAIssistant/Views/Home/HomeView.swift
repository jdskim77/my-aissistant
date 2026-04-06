import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.wisdomManager) private var wisdomManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @Query(sort: \HabitItem.createdAt) private var allHabits: [HabitItem]

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
                compassScores: nil,  // Compass scores wired in Phase 2
                currentMood: nil,    // Mood from check-ins wired in Phase 2
                streak: streak
            ) ?? WisdomManager.todayQuote() {
                Section {
                    wisdomCard(quote: quote)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            // Stats bar
            Section {
                statsBar
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
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
                    .buttonStyle(.plain)
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

    private func wisdomCard(quote: WisdomManager.Quote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.accentWarm)
                Text("Daily Wisdom")
                    .font(AppFonts.label(12))
                    .foregroundColor(AppColors.accentWarm)
            }

            Text("\"\(quote.text)\"")
                .font(AppFonts.display(16))
                .foregroundColor(AppColors.textPrimary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)

            Text("- \(quote.author)")
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accentWarm.opacity(0.2), lineWidth: 1)
        )
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

            // Next check-in pill
            Button {
                showingCheckIn = true
            } label: {
                let next = CheckInTime.next()
                HStack(spacing: 6) {
                    Text(next.icon)
                        .font(.system(size: 14))
                    Text(next.timeLabel)
                        .font(AppFonts.label(12))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.card)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .offset(y: appeared ? 0 : 15)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 16) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(AppColors.border, lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: completionFraction)
                    .stroke(AppColors.completionGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(completionFraction * 100))%")
                    .font(AppFonts.label(9))
                    .foregroundColor(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(completedTodayCount) of \(totalTodayCount) done")
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)
                if streak > 0 {
                    Text("\(streak)-day streak 🔥")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Spacer()

            // Overdue badge
            if !overdueTasks.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text("\(overdueTasks.count) overdue")
                        .font(AppFonts.label(12))
                }
                .foregroundColor(AppColors.overdueRed)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColors.overdueBg)
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        )
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
        .buttonStyle(.plain)
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
                .buttonStyle(.plain)

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
        .buttonStyle(.plain)
    }
}
