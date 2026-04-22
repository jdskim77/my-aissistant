import SwiftUI
import SwiftData

/// Enumerates the sheets Home can present. A single `@State private var
/// activeSheet: HomeSheet?` drives a single `.sheet(item:)` so two triggers
/// can never race and silently drop one presentation (prior behaviour with
/// five parallel `.sheet()` modifiers).
enum HomeSheet: Identifiable {
    case todaysContext
    case checkIn
    case habits
    case addHabit
    case reschedule(TaskItem)
    /// Full Schedule view (week/month navigation + add-task form) as a
    /// sheet. Replaces the old Schedule tab that was removed when
    /// Coach took its place in the bottom bar. Accessible via the
    /// calendar icon in the Today header or deep-link from TASK
    /// notifications.
    case schedule

    var id: String {
        switch self {
        case .todaysContext: return "todaysContext"
        case .checkIn: return "checkIn"
        case .habits: return "habits"
        case .addHabit: return "addHabit"
        case .reschedule(let task): return "reschedule-\(task.id)"
        case .schedule: return "schedule"
        }
    }
}

extension Notification.Name {
    /// Posted by ContentView when a TASK-category notification is
    /// tapped and we want Today to auto-open the Schedule sheet.
    /// HomeView subscribes and sets `activeSheet = .schedule`.
    static let openScheduleSheet = Notification.Name("openScheduleSheet")
}

struct HomeView: View {
    @Binding var selectedTab: Tab
    @Environment(\.taskManager) private var taskManager
    @Environment(\.habitManager) private var habitManager
    @Environment(\.insightEngine) private var insightEngine
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.wisdomManager) private var wisdomManager
    @Environment(\.balanceManager) private var balanceManager
    @Environment(\.weatherManager) private var weatherManager
    @Environment(\.balancePulseBus) private var balancePulseBus
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.date) private var allTasks: [TaskItem]
    @Query(sort: \HabitItem.createdAt) private var allHabits: [HabitItem]
    @Query(filter: #Predicate<CheckInRecord> { $0.completed == true },
           sort: \CheckInRecord.date, order: .reverse) private var allCheckIns: [CheckInRecord]

    @State private var appeared = false
    /// Single mutually-exclusive sheet slot. Replaces the prior stack of five
    /// independent `.sheet()` modifiers so the five triggers can't race each
    /// other (SwiftUI only presents one at a time — the old layout made the
    /// losing state silently vanish).
    @State private var activeSheet: HomeSheet?
    // Collapse state is persisted so the user's disclosure choices survive
    // relaunches — matches Overdue/Completed/Tomorrow/Life Balance/Habits
    // behaviour (all collapsible, all remembered).
    @AppStorage("home.overdue.expanded") private var overdueExpanded = true
    @AppStorage("home.completed.expanded") private var completedExpanded = false
    @AppStorage("home.tomorrow.expanded") private var tomorrowExpanded = false
    @AppStorage("home.habits.expanded") private var habitsExpanded = true
    // Section visibility — user can hide non-essential cards in Settings →
    // Home Sections. Today's hero + active tasks are never hidden.
    @AppStorage("home.show.lifeBalance") private var showLifeBalance = true
    @AppStorage("home.show.habits") private var showHabits = true
    @AppStorage("home.show.tomorrow") private var showTomorrow = true
    @AppStorage("home.show.wisdom") private var showWisdom = true
    @State private var taskToDelete: TaskItem?
    @State private var showingDoneHabits = false
    @State private var rescheduleDate = Date()
    @State private var greetingManager = GreetingManager()
    @State private var greetingOrbActive = false
    @State private var orbTask: Task<Void, Never>?
    @State private var dismissTask: Task<Void, Never>?
    @State private var celebrationMilestone: Int?
    /// Owns in-flight "task → Life Balance" particles and the landing
    /// pulseRequest the BalancePulseCard watches. Lives on Home (not in an
    /// env/manager) because source and target are both Home-local — no other
    /// screen has a BalancePulseCard to fly to.
    @State private var particleAnimator = ParticleAnimator()
    /// Latest known center of each dimension bar in the particle coord space.
    /// Populated by `BalancePulseCard`'s dimensionBar geometry; read at the
    /// moment of fire so the particle aims at where the bar is right now.
    @State private var dimensionBarCenters: [LifeDimension: CGPoint] = [:]
    /// Last bus-pulse token the HomeView bus-bridge actually forwarded to
    /// the animator. Prevents a stale pulse from replaying as an in-place
    /// pulse when the user returns to Home within the 3s staleness window.
    @State private var lastHandledBusToken: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tracks insight-banner dismissal within this view session so a user who
    /// dismisses the banner doesn't see it flash back during the same visit.
    /// Re-evaluated on `.active` scene phase transitions so the per-day key
    /// rollover at midnight takes effect without requiring a relaunch.
    @State private var insightBannerDismissed = PatternInsightBanner.isDismissedToday()

    // MARK: - Computed

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    // MARK: - Home Stage (FTUE gating)
    //
    // The screen is built for a returning user with data. A literal day-0 user
    // (no check-ins ever, no completed tasks) sees a 0% ring, empty balance
    // bars, and repeated "empty" empty-states — the screen says "you are
    // nothing" five times. `.day0` collapses the screen down to a single
    // "Start Here" card until the user generates real data, then the rest of
    // Home unlocks naturally.

    private enum HomeStage { case day0, normal }

    /// Once the user has reached `.normal`, record it in UserDefaults so
    /// the screen never regresses to the Start-Here experience. Prior
    /// behavior: deleting the last completed task with no check-ins yet
    /// collapsed the whole Hero/Balance/Insight stack back to day-0 —
    /// jarring for anyone who'd already explored the app.
    @AppStorage("home.hasReachedNormalStage") private var hasReachedNormalStage: Bool = false

    private var homeStage: HomeStage {
        if hasReachedNormalStage { return .normal }
        let hasCheckIn = !allCheckIns.isEmpty
        let hasCompletedTask = allTasks.contains { $0.done }
        return (hasCheckIn || hasCompletedTask) ? .normal : .day0
    }

    /// Called from .onChange handlers on allCheckIns / allTasks so the
    /// one-time flip from day0 → normal happens outside `body`. We don't
    /// un-set on deletion — once a user has activated, they stay in the
    /// normal experience even if they later delete all their data.
    private func promoteFromDay0IfNeeded() {
        guard !hasReachedNormalStage else { return }
        let hasCheckIn = !allCheckIns.isEmpty
        let hasCompletedTask = allTasks.contains { $0.done }
        if hasCheckIn || hasCompletedTask {
            hasReachedNormalStage = true
        }
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
        // Cap the overdue lookback at 30 days so calendar-imported users
        // don't land on Home with a 50-row pile of years-old incomplete
        // events. Tasks older than the window are still in Schedule; they
        // just stop screaming for attention on Home.
        let cutoff = Calendar.current.safeDate(byAdding: .day, value: -30, to: startOfToday)
        return allTasks.filter { $0.date < startOfToday && $0.date >= cutoff && !$0.done }
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

    /// Habits not yet completed today — the "needs attention" set. Sorted by
    /// active streak so a 12-day streak at risk sits above a brand-new habit.
    private var habitsToDoToday: [HabitItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return activeHabits.filter { !$0.isCompletedOn(today) }
            .sorted { $0.currentStreak() > $1.currentStreak() }
    }

    /// Habits already done today. Surfaced as a collapsed "✓ N done" chip so
    /// the main list stays short and focused on what's left.
    private var habitsDoneToday: [HabitItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return activeHabits.filter { $0.isCompletedOn(today) }
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Memoize weekly scores + derived stats once per body evaluation.
            // Computing all three pieces in one let avoids a second trip
            // through `weeklyScores → balanceScore → weeklyScores` that the
            // older form did via separate `harmonyScore()` + `weeklyScores()`
            // calls. Skip the work entirely on day-0 since nothing in the
            // .day0 branch reads them.
            // V3: per-dim today-fill + yesterday-tick memoized per body
            // eval so the BalancePulseCard rendering doesn't re-query
            // BalanceManager four times per frame during scroll.
            let snapshot: HomeBalanceSnapshot = {
                guard homeStage != .day0, let bm = balanceManager else {
                    return HomeBalanceSnapshot.empty
                }
                var todayFill: [LifeDimension: Double] = [:]
                var yesterdayTick: [LifeDimension: Double?] = [:]
                var todayPoints: [LifeDimension: Double] = [:]
                for dim in LifeDimension.scored {
                    todayFill[dim] = bm.todayFill(for: dim)
                    yesterdayTick[dim] = bm.yesterdayTickValue(for: dim)
                    todayPoints[dim] = bm.todayPoints(for: dim)
                }
                // Representative daily target for the caption — scored dims
                // share the same default; if the user later customizes per-dim
                // targets we'd display the median or per-dim labels.
                let targetDim = LifeDimension.scored.first ?? .physical
                return HomeBalanceSnapshot(
                    scores: bm.weeklyScores(),
                    harmony: bm.harmonyScore(),
                    stage: bm.harmonyStage(),
                    hasData: bm.hasRealData(),
                    todayFill: todayFill,
                    yesterdayTick: yesterdayTick,
                    todayPoints: todayPoints,
                    dailyTarget: Int(bm.dailyTarget(for: targetDim))
                )
            }()

            if homeStage == .day0 {
                // MARK: - Day 0: Start-Here card only
                //
                // The most hostile state for a new user is the default Home
                // rendering at 0%, with empty bars and "no data" empty states
                // repeated five times. `.day0` swaps Hero + Balance + Insight
                // for a single on-ramp card. The first completed check-in or
                // task flips the stage to `.normal` and the rest of the screen
                // unlocks — a deliberate Peak-End reveal.
                Section {
                    startHereCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                // MARK: - Normal stage: Hero + Balance + content

                // Pattern Insight surfacing banner — only appears when
                // InsightEngine has enough data to compute a real insight,
                // and only when the user hasn't dismissed it today.
                if let insight = insightEngine?.todayInsight(), !insightBannerDismissed {
                    Section {
                        PatternInsightBanner(insight: insight) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                insightBannerDismissed = true
                            }
                            PatternInsightBanner.markDismissedToday()
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                // Today hero card (dual-ring + contextual check-in action)
                Section {
                    todayHeroCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                // Balance Pulse — Pillar 3 (Whole-Life Balance). Now also hosts
                // the Daily Wisdom as a small italic tagline so we don't need
                // a separate Wisdom card competing for attention above. The
                // card is collapsible (chevron in its header) and the tagline
                // is conditionally passed based on the Wisdom visibility
                // toggle in Settings → Home Sections.
                if showLifeBalance {
                    Section {
                        BalancePulseCard(
                            todayFill: snapshot.todayFill,
                            todayPoints: snapshot.todayPoints,
                            yesterdayTick: snapshot.yesterdayTick,
                            dailyTarget: snapshot.dailyTarget,
                            harmonyScore: snapshot.harmony,
                            stage: snapshot.stage,
                            hasData: snapshot.hasData,
                            flightPulse: particleAnimator.pulseRequest,
                            tagline: showWisdom ? wisdomTagline(balanceScores: snapshot.scores) : nil,
                            onTapCompass: { selectedTab = .compass }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            // Habits section — collapsible, auto-curated.
            //
            // The section only renders habits that still need attention today;
            // completed ones collapse into a "✓ N done today" disclosure so a
            // user with 6 habits doesn't see a 6-row wall once they've
            // finished them. The whole section can also be collapsed from its
            // header (chevron) for users who prefer a quieter Home.
            if showHabits {
                if activeHabits.isEmpty {
                    // Empty state — user has never added a habit. Previously
                    // the whole section was suppressed, which meant the only
                    // way to add a habit from Home was... nowhere. Surface a
                    // minimal CTA so Pillar 1 (daily ritual) has an on-ramp.
                    Section {
                        emptyHabitsCard
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        if habitsExpanded {
                            habitsCard
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        habitsHeader
                    }
                }
            }

            // Overdue section
            if !overdueTasks.isEmpty {
                Section {
                    if overdueExpanded {
                        ForEach(overdueTasks, id: \.id) { task in
                            TaskCard(
                                task: task,
                                isOverdue: true,
                                onFlightLaunch: flightLaunchHandler
                            ) {
                                handleToggle(task)
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
                                    activeSheet = .reschedule(task)
                                    rescheduleDate = TaskManager.rescheduleSeedDate(for: task)
                                } label: {
                                    Label("Reschedule", systemImage: "calendar.badge.clock")
                                }
                                .tint(AppColors.skyBlue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    handleToggle(task)
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
                        handleToggle(event)
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
                            handleToggle(event)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle.fill")
                        }
                        .tint(AppColors.completionGreen)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }

                // Active tasks
                if todayActiveTasks.isEmpty && todayCalendarEvents.isEmpty && overdueTasks.isEmpty {
                    // In day-0 we skip the "No tasks today" message because
                    // the Start-Here card is already the primary CTA and the
                    // extra empty state just piles on.
                    if homeStage != .day0 {
                        emptyActiveState
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16))
                    }
                } else {
                    ForEach(todayActiveTasks, id: \.id) { task in
                        TaskCard(task: task, onFlightLaunch: flightLaunchHandler) {
                            handleToggle(task)
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
                                activeSheet = .reschedule(task)
                                rescheduleDate = TaskManager.rescheduleSeedDate(for: task)
                            } label: {
                                Label("Reschedule", systemImage: "calendar.badge.clock")
                            }
                            .tint(AppColors.skyBlue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                handleToggle(task)
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle.fill")
                            }
                            .tint(AppColors.completionGreen)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }
            } header: {
                // Hide the "Today" header on day 0 so the Start-Here card is
                // the unambiguous focal point.
                if homeStage == .normal || !todayActiveTasks.isEmpty || !todayCalendarEvents.isEmpty {
                    Text("Today")
                        .font(AppFonts.heading(15))
                        .foregroundColor(AppColors.textPrimary)
                        .textCase(nil)
                }
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
                                // Undo/uncomplete — no pulse (we only celebrate
                                // forward motion).
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

            // Tomorrow section — hidden entirely when the user disables it in
            // Settings → Home Sections.
            if showTomorrow && !tomorrowTasks.isEmpty {
                Section {
                    if tomorrowExpanded {
                        ForEach(tomorrowTasks, id: \.id) { task in
                            TaskCard(task: task, onFlightLaunch: flightLaunchHandler) {
                                handleToggle(task)
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
                                    activeSheet = .reschedule(task)
                                    rescheduleDate = TaskManager.rescheduleSeedDate(for: task)
                                } label: {
                                    Label("Reschedule", systemImage: "calendar.badge.clock")
                                }
                                .tint(AppColors.skyBlue)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    handleToggle(task)
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

            // "Hidden sections" footer — only appears when the user has
            // switched off at least one optional Home card. Points back to
            // Settings so a returning user doesn't think the app regressed
            // when their Home looks sparser than they remember.
            if hiddenHomeSectionCount > 0 {
                Section {
                    hiddenSectionsFooter
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
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
        .animation(.easeInOut(duration: 0.35), value: homeStage)
        // Shared coord space for TaskCard checkbox (source) and
        // BalancePulseCard dimension bars (targets). Both ends resolve
        // positions in this space so the overlay can draw a single path
        // across the List/Card boundary.
        .coordinateSpace(name: particleCoordinateSpace)
        .onPreferenceChange(DimensionBarPositionKey.self) { positions in
            // Scrolling the List moves the bars within the named coord
            // space every frame. Only commit updates when a dimension's
            // center has moved ≥2pt — sub-pixel drift from scroll doesn't
            // change where the particle should aim.
            var significant = false
            for (dim, newPt) in positions {
                guard let prev = dimensionBarCenters[dim] else { significant = true; break }
                if abs(prev.x - newPt.x) > 2 || abs(prev.y - newPt.y) > 2 {
                    significant = true
                    break
                }
            }
            if significant || positions.count != dimensionBarCenters.count {
                dimensionBarCenters = positions
            }
        }
        .overlay {
            // Wave prototype (Option A). Swap to `ParticleLayer(animator:)`
            // to restore the original 8pt-particle-with-trail visual. Both
            // share the same animator API + coord space, so toggling is a
            // one-line change.
            //
            // BUG-07 fix: deliberately NOT `.ignoresSafeArea()`. Source and
            // target coords are captured inside the List's named coord space
            // (which respects safeArea). If this overlay ignored safeArea,
            // its local origin would shift upward by `safeAreaTop` relative
            // to those captured coords — the wave would render visibly above
            // its intended y. Keeping safeArea means the overlay's origin
            // matches the List's, so source/target y values render where
            // they were captured. The wave's opacity envelope fades it to
            // zero by t=0.8, so clipping at the overlay's top is invisible.
            WaveLayer(animator: particleAnimator)
        }
        // Bridge bus pulses (Watch sync, Focus auto-complete, recurring
        // generation) into in-place pulses on the bar. Token memory
        // prevents a re-pulse when the user returns to Home within the
        // 3s staleness window — the `.onChange` on `.latest?.token` WILL
        // fire on re-subscription with the same token it previously saw.
        .onChange(of: balancePulseBus?.latest?.token) { _, newToken in
            guard let newToken, newToken != lastHandledBusToken else { return }
            guard let pulse = balancePulseBus?.latest, !pulse.isStale() else {
                lastHandledBusToken = newToken
                return
            }
            guard particleAnimator.shouldHandleBusPulse(pulse.dimension) else {
                lastHandledBusToken = newToken
                return
            }
            lastHandledBusToken = newToken
            particleAnimator.pulseInPlace(dimension: pulse.dimension)
        }
        .onAppear {
            // Pre-warm the haptic generator so the first landing vibrates
            // in sync with the visual instead of lagging 100–200ms.
            particleAnimator.prepareHaptics()
            // Seed the bus token so the initial onChange fire on re-appear
            // doesn't replay the last pulse as an in-place pulse.
            lastHandledBusToken = balancePulseBus?.latest?.token
        }
        .onDisappear {
            // Cancel any in-flight particle landings so their haptic +
            // pulseRequest don't fire while the user is on another tab.
            particleAnimator.cancelAll()
        }
        // Reset the "done habits" inline disclosure when it no longer has
        // content or when the user collapses the whole Habits section.
        // Without this, the disclosure state leaks across day rollovers and
        // section collapse cycles — users re-expanding Habits the next day
        // would see the chip pre-expanded from yesterday.
        .onChange(of: habitsDoneToday.count) { _, newCount in
            if newCount == 0 { showingDoneHabits = false }
        }
        .onChange(of: habitsExpanded) { _, nowExpanded in
            if !nowExpanded { showingDoneHabits = false }
        }
        .onChange(of: scenePhase) { _, phase in
            // When the app returns to foreground, re-check the per-day
            // dismissal key. Without this the insight banner would stay
            // hidden across the midnight rollover if the user left Home
            // visible overnight.
            if phase == .active {
                insightBannerDismissed = PatternInsightBanner.isDismissedToday()
                // Weather cache is 30 min; after a long background gap the
                // Home chip would otherwise keep showing stale conditions
                // until the user manually tapped it.
                Task { await weatherManager?.refreshIfAuthorizedAndStale() }
            }
        }
        .onChange(of: allCheckIns.isEmpty) { _, _ in
            promoteFromDay0IfNeeded()
        }
        .onChange(of: allTasks.contains(where: { $0.done })) { _, _ in
            promoteFromDay0IfNeeded()
        }
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

            // Re-check insight dismissal — the UserDefaults key rolls daily.
            insightBannerDismissed = PatternInsightBanner.isDismissedToday()

            // Catch any pending day0 → normal promotion on appear, in case
            // data arrived while another tab was active.
            promoteFromDay0IfNeeded()

            // Generate contextual AI greeting
            let todayTasks = taskManager?.todayTasks() ?? []
            let highPriority = taskManager?.highPriorityUpcoming(limit: 1) ?? []
            // Habits 2+ target-days overdue
            let slippingHabits = activeHabits
                .compactMap { habit -> (title: String, days: Int)? in
                    guard let days = habit.daysSinceLastCompletion(), days >= 2 else { return nil }
                    return (habit.title, days)
                }
                .sorted { $0.days > $1.days }
                .map(\.title)
            let isNew = greetingManager.generateGreetingIfNeeded(
                todayTaskCount: todayTasks.count,
                completedTodayCount: todayTasks.filter(\.done).count,
                highPriorityTitles: highPriority.map(\.title),
                completionRate: patternEngine?.completionRate() ?? 0,
                streak: patternEngine?.currentStreak() ?? 0,
                slippingHabitTitles: slippingHabits
            )

            // Pulse the orb briefly on fresh greetings
            if isNew {
                greetingOrbActive = true
                orbTask?.cancel()
                orbTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    greetingOrbActive = false
                }
            }

            // Auto-dismiss greeting after 30 seconds
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                greetingManager.dismissGreeting()
            }
        }
        // Refresh weather silently — auto-cancels if the user leaves Home
        // mid-fetch. Never prompts on launch (lazy permission).
        .task {
            await weatherManager?.refreshIfAuthorizedAndStale()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .todaysContext:
                TodaysContextSheet(
                    snapshot: weatherManager?.latest,
                    isLoading: weatherManager?.isLoading ?? false,
                    isAuthorized: weatherManager?.isAuthorized ?? false,
                    isDenied: weatherManager?.isDenied ?? false,
                    currentSlot: CheckInTime.current(),
                    onRefresh: { Task { await weatherManager?.refresh() } }
                )
            case .checkIn:
                CheckInDetailView(timeSlot: CheckInTime.next())
            case .habits:
                HabitsView()
            case .addHabit:
                HabitFormView(mode: .create)
            case .reschedule(let task):
                rescheduleSheet(for: task)
            case .schedule:
                NavigationStack {
                    ScheduleView()
                        .navigationTitle("Schedule")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    activeSheet = nil
                                }
                            }
                        }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openScheduleSheet)) { _ in
            // If another sheet is already on screen (CheckIn, Habits,
            // Reschedule, etc.), setting activeSheet = .schedule
            // silently drops the request because SwiftUI only
            // presents one `.sheet(item:)` at a time. Close the
            // current sheet first, then open Schedule on the next
            // runloop — this keeps TASK-notification deep-links
            // reliable regardless of what sheet is already up.
            // Fix for BUG-19.
            if activeSheet != nil && activeSheet?.id != HomeSheet.schedule.id {
                activeSheet = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    activeSheet = .schedule
                }
            } else {
                activeSheet = .schedule
            }
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

    // MARK: - Task completion

    /// Home's single toggle entry point. The balance pulse itself is fired
    /// inside `TaskManager.toggleCompletion` so that *every* completion path
    /// (Home list, Focus timer, Schedule swipe, TaskDetail, Watch sync)
    /// produces the same visible Compass movement — without Home needing to
    /// know about those call sites.
    private func handleToggle(_ task: TaskItem) {
        Haptics.success()
        withAnimation(.spring(response: 0.3)) {
            taskManager?.toggleCompletion(task)
        }
    }

    /// Passed into TaskCard so forward completions launch a particle flight
    /// toward the Life Balance card. The closure is always supplied — Reduce
    /// Motion is handled inside by routing to `pulseInPlace` (accessible
    /// equivalent: the bar pulses in place, no particle). Also falls back to
    /// `pulseInPlace` when the target bar hasn't been laid out yet (e.g. the
    /// user collapsed the Life Balance card, so its dimensionBars aren't
    /// contributing frames), which avoids firing a particle into (0,0).
    private var flightLaunchHandler: ((CGPoint, LifeDimension) -> Void)? {
        { source, dimension in
            if self.reduceMotion {
                self.particleAnimator.pulseInPlace(dimension: dimension)
                return
            }
            // Target resolution:
            //   (1) If the Balance bar is laid out and visible in the named
            //       coord space, aim for its centre.
            //   (2) Otherwise (Balance collapsed, hidden in Settings, pushed
            //       off-screen by a long habits list, or simply not yet
            //       measured on first-mount) aim just past the top of the
            //       screen. The wave still rises visibly from the tap point —
            //       the user gets "energy flowed upward" even when there's
            //       no bar to land on. The bar pulse + haptic that fire on
            //       arrival are no-ops in that case, which is exactly what
            //       we want.
            //
            // BUG-03 fix: the synthetic target was `source.y - 500` (fixed
            // offset). On small / short screens (iPhone SE portrait, iPad
            // landscape with a tap near the top) most of the 700ms was spent
            // rendering off-screen. `y: -140` ends the wave centre exactly
            // one bandHeight above the overlay top regardless of where the
            // tap came from, keeping the visible portion at 85–95% of the
            // flight duration on every device.
            // If the Balance bar isn't laid out (card collapsed, hidden,
            // or measured at zero) skip the particle flight entirely and
            // fall back to `pulseInPlace`. The previous synthetic
            // `(source.x, -140)` target animated off-screen, which meant
            // the user paid 700ms of animation cost for a visual they
            // couldn't see. The collapsed-flash border — which we ALSO
            // fire via the bus bridge — is the authoritative signal when
            // the bar isn't visible.
            guard let measured = self.dimensionBarCenters[dimension], measured != .zero else {
                self.particleAnimator.pulseInPlace(dimension: dimension)
                return
            }
            self.particleAnimator.fire(dimension: dimension, from: source, to: measured)
        }
    }

    // MARK: - Wisdom tagline (inlined into Balance Pulse)

    /// Produces a compact (text, author) tuple for the wisdom tagline shown
    /// inside the Balance Pulse card. Early-returns nil on day-0 since the
    /// card isn't rendered — avoids building the score dict and calling the
    /// quote selector on the hot path every body evaluation.
    private func wisdomTagline(balanceScores: [LifeDimension: Double]) -> (text: String, author: String)? {
        guard homeStage == .normal else { return nil }
        let quote = wisdomManager?.todayQuote(
            compassScores: balanceScores.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            currentMood: nil,
            streak: streak
        ) ?? WisdomManager.todayQuote()
        guard let q = quote else { return nil }
        return (q.text, q.author)
    }

    // MARK: - Day-0 Start-Here card

    /// The single card shown on a literal first-use Home screen. It replaces
    /// the Hero + Balance + Insight stack until the user has any real data.
    /// Tapping "Start check-in" routes through the same sheet used in the
    /// Hero action row on subsequent visits — flipping homeStage to .normal
    /// on save (which updates `allCheckIns` via @Query).
    private var startHereCard: some View {
        let slot = CheckInTime.current()
        return VStack(spacing: 14) {
            HStack {
                Text("START HERE")
                    .font(AppFonts.label(11))
                    .tracking(0.8)
                    .foregroundColor(AppColors.textMuted)
                Spacer()
            }

            VStack(spacing: 6) {
                Image(systemName: slot.sfSymbol)
                    .font(.system(size: 40, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(slot.color)

                Text("Let's start your day")
                    .font(AppFonts.display(20))
                    .foregroundColor(AppColors.textPrimary)

                Text("A 30-second check-in, four times a day, turns how you feel into trends you can see. Your Compass fills in as you go.")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
            .padding(.top, 4)

            Button {
                Haptics.light()
                activeSheet = .checkIn
            } label: {
                HStack(spacing: 8) {
                    Text("Start \(slot.rawValue) check-in")
                        .font(AppFonts.bodyMedium(15))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .cornerRadius(12)
            }
            .buttonStyle(.scale)
            .accessibilityLabel("Start your first \(slot.rawValue) check-in")

            Text("It only takes 30 seconds")
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textMuted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColors.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            RadialGradient(
                                colors: [slot.color.opacity(0.08), Color.clear],
                                center: .top,
                                startRadius: 10,
                                endRadius: 260
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        )
        .offset(y: appeared ? 0 : 15)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Today Hero Card (dual-ring)
    //
    // Apple Fitness pattern: outer ring = tasks (green), inner ring = check-ins
    // (accent). One composed graphic replaces the old ring + breakdown row
    // (which was showing two representations of the same data).

    /// Fraction of today's tasks that are complete. Zero when no tasks exist.
    private var tasksFraction: Double {
        guard totalTodayCount > 0 else { return 0 }
        return min(1, Double(completedTodayCount) / Double(totalTodayCount))
    }

    /// Fraction of today's 4 check-in slots that have been logged.
    private var checkInFraction: Double {
        min(1, Double(todayCheckInCount) / 4.0)
    }

    /// Blended day-percentage shown in the ring center.
    ///
    /// When the user has NO tasks scheduled today (totalTodayCount == 0),
    /// the check-ins become the sole signal — completing all 4 check-ins
    /// should read as "100% done" rather than "4 of 4+0 = bucket division
    /// by a fake +4 task-count that's really counting check-ins." Previously
    /// a user with 0 tasks and 4 check-ins read as 100% (correct) but a
    /// user with 0 tasks and 0 check-ins at 6 AM read as 0% of a 4-unit
    /// bucket they hadn't scheduled — a misleading "you've done nothing
    /// today" when they haven't had breakfast yet.
    private var dayCompletionFraction: Double {
        // Task side contributes when tasks exist; check-in side always
        // weighs the 4 slots. Sum only the units the user actually signed
        // up for. If nothing's scheduled AND no check-ins yet, fraction
        // is 0 but the ring UI shows it as "ready for today" copy upstream.
        let taskUnits = max(0, totalTodayCount)
        let checkInUnits = 4
        let totalUnits = taskUnits + checkInUnits
        guard totalUnits > 0 else { return 0 }
        let doneUnits = completedTodayCount + todayCheckInCount
        return min(1.0, Double(doneUnits) / Double(totalUnits))
    }

    private var todayHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // TODAY label only — streak moved out (lived in the corner as
            // cosmetic chrome; not load-bearing for today's screen).
            Text("TODAY")
                .font(AppFonts.label(11))
                .tracking(0.8)
                .foregroundColor(AppColors.textMuted)

            // Hero row: compact ring on the left + stats stacked to the right.
            // Saves ~60pt of vertical versus the centered-ring layout and
            // reads as a single horizontal "status line" rather than a
            // dedicated ring section.
            //
            // Vertical alignment is `.center` so at XXL Dynamic Type the
            // ring stays vertically centered against the growing % text
            // stack (otherwise the ring hangs above the baseline).
            //
            // The whole row is a single VoiceOver element reading
            // `heroAccessibilityLabel`. Without `.ignore` + top-level label,
            // VO reads the ring label and the adjacent "% of day done" text
            // as two separate announcements — the exact BUG-01 regression.
            // `heroAccessibilityLabel` already phrases both counts, so the
            // legend row's detail stays reachable via that label.
            HStack(alignment: .center, spacing: 14) {
                compactDualRing

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(dayCompletionFraction * 100))%")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)
                            .monospacedDigit()
                        Text(dayCompletionFraction >= 1 ? "all done" : "of day done")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }
                    HStack(spacing: 12) {
                        legendItem(color: AppColors.completionGreen, label: "Tasks \(completedTodayCount)/\(totalTodayCount)")
                        legendItem(color: AppColors.accent, label: "Check-ins \(todayCheckInCount)/4")
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)

            // Slot icons strip — light/filled by completion state.
            HStack(spacing: 8) {
                ForEach(CheckInTime.allCases) { slot in
                    Image(systemName: slot.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSlotCompletedToday(slot) ? slot.color : AppColors.border)
                }
                Spacer(minLength: 0)
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
            }

            // Action slot — only renders in .prominent / .complete states.
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

    /// Compact dual-ring: outer = tasks, inner = check-ins. Sized to fit as
    /// a left-anchored glyph inside the hero row, with the percentage label
    /// moved out to the right (see `todayHeroCard`). No center text here —
    /// the big % text lives in the adjacent VStack so font scaling doesn't
    /// overrun the ring.
    ///
    /// When both rings are empty (normal stage, 0 tasks and 0 check-ins
    /// today) the inner empty track is suppressed so the card reads as a
    /// single "starting fresh" ring rather than a concentric target/bullseye
    /// icon. The inner track re-appears as soon as either fraction > 0.
    private var compactDualRing: some View {
        let outerSize: CGFloat = 60
        let innerSize: CGFloat = 40
        let lineWidth: CGFloat = 5
        let hasAnyProgress = tasksFraction > 0 || checkInFraction > 0
        return ZStack {
            // Outer ring — Tasks. Guarded on >0 so an empty track doesn't
            // render a rounded-cap dot from a forced 0.001 trim.
            Circle()
                .stroke(AppColors.border, lineWidth: lineWidth)
                .frame(width: outerSize, height: outerSize)
            if tasksFraction > 0 {
                Circle()
                    .trim(from: 0, to: tasksFraction)
                    .stroke(AppColors.completionGreen, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: outerSize, height: outerSize)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: tasksFraction)
            }

            // Inner ring — Check-ins. Only render when either dimension has
            // progress; a paired empty inner track next to an empty outer
            // track reads as a target icon instead of "nothing yet today."
            if hasAnyProgress {
                Circle()
                    .stroke(AppColors.border, lineWidth: lineWidth)
                    .frame(width: innerSize, height: innerSize)
                if checkInFraction > 0 {
                    Circle()
                        .trim(from: 0, to: checkInFraction)
                        .stroke(AppColors.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .frame(width: innerSize, height: innerSize)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: checkInFraction)
                }
            }
        }
        .frame(width: outerSize, height: outerSize)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textSecondary)
                .monospacedDigit()
        }
    }

    /// Constructs a humane description of the ring for VoiceOver. Avoids
    /// the confusing "0 of 0 tasks" reading when the user has no tasks
    /// scheduled — we phrase it differently in that case.
    private var heroAccessibilityLabel: String {
        let percent = Int(dayCompletionFraction * 100)
        let taskPhrase: String
        if totalTodayCount == 0 {
            taskPhrase = "no tasks scheduled"
        } else {
            taskPhrase = "\(completedTodayCount) of \(totalTodayCount) tasks complete"
        }
        let checkPhrase = "\(todayCheckInCount) of 4 check-ins"
        return "Today: \(percent) percent done. \(taskPhrase), \(checkPhrase)."
    }

    /// Adaptive bottom slot: shows whichever action is most relevant.
    @ViewBuilder
    private var heroActionRow: some View {
        switch checkInCardState {
        case .prominent(let slot):
            Button { activeSheet = .checkIn } label: {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        case .progress:
            // Between active windows — no urgent action.
            Button { activeSheet = .checkIn } label: {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(AppFonts.display(24))
                    .foregroundColor(AppColors.textPrimary)
                Text(formattedDate)
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Calendar icon opens the full Schedule view as a sheet.
            // Replaces the old Schedule tab (removed when Coach took
            // slot 1 in the bottom bar). Tap-target is 44pt via the
            // explicit frame.
            Button {
                Haptics.selection()
                activeSheet = .schedule
            } label: {
                Image(systemName: "calendar")
                    .font(AppFonts.heading(18))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open schedule")
            .accessibilityHint("Week and month view with task add")

            // Weather chip — aligns with the date line via bottom alignment.
            WeatherChip(
                snapshot: weatherManager?.latest,
                isLoading: weatherManager?.isLoading ?? false,
                isAuthorized: weatherManager?.isAuthorized ?? false,
                onTap: { activeSheet = .todaysContext }
            )
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
        // Announce as a section header with its expand state, so VoiceOver
        // reads "Overdue, 4. Collapsed, header" instead of four disjoint
        // elements (icon, label, chevron, button role).
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
        .accessibilityHint("Double tap to \(isExpanded.wrappedValue ? "collapse" : "expand")")
        .accessibilityAddTraits(.isHeader)
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
            Text("Tap the calendar icon above to add a task")
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

    // MARK: - Hidden Sections Footer

    /// How many of the four optional Home cards are currently hidden via
    /// Settings → Home Sections. Drives the footer visibility below.
    private var hiddenHomeSectionCount: Int {
        var count = 0
        if !showLifeBalance { count += 1 }
        if !showHabits { count += 1 }
        if !showTomorrow { count += 1 }
        if !showWisdom { count += 1 }
        return count
    }

    /// Tiny muted footer shown when the user has hidden one or more cards.
    /// Tapping jumps to the Settings tab so they can toggle cards back on
    /// without having to remember where the toggles live.
    private var hiddenSectionsFooter: some View {
        Button {
            Haptics.light()
            selectedTab = .settings
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                Text("\(hiddenHomeSectionCount) section\(hiddenHomeSectionCount == 1 ? "" : "s") hidden · Manage in Settings")
                    .font(AppFonts.caption(12))
                Spacer(minLength: 0)
            }
            .foregroundColor(AppColors.textMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hiddenHomeSectionCount) Home sections hidden. Open Settings to manage.")
    }

    // MARK: - Habits Empty State

    /// Shown on Home when the user has zero active habits. Replaces the
    /// previous behaviour of hiding the whole section (which left Home with
    /// no discoverable path to create a habit — the HabitsView sheet was
    /// reachable only via deep-linked intents or Settings).
    private var emptyHabitsCard: some View {
        Button {
            Haptics.light()
            activeSheet = .addHabit
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background(AppColors.accent.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Build a habit")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Small daily actions that feed your balance")
                        .font(AppFonts.caption(12))
                        .foregroundColor(AppColors.textMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accent)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.card)
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.scale)
        .accessibilityLabel("Build a habit. Add your first habit.")
    }

    // MARK: - Habits Header (collapsible)

    /// Section header for Habits. Tapping the title area toggles collapse
    /// (chevron rotates); the + button stays as a separate tap target so the
    /// user can add a habit without first expanding the section.
    private var habitsHeader: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    habitsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.accent)
                    Text(habitsHeaderTitle)
                        .font(AppFonts.heading(15))
                        .foregroundColor(AppColors.textPrimary)
                        .textCase(nil)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppColors.textMuted)
                        .rotationEffect(.degrees(habitsExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Consolidate label + chevron into one VO element and announce
            // it as a section header. The label reads e.g. "Habits, 3 to do"
            // instead of four separate elements (leaf icon, title text,
            // chevron, button).
            .accessibilityElement(children: .combine)
            .accessibilityLabel(habitsHeaderAccessibilityLabel)
            .accessibilityValue(habitsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Double tap to \(habitsExpanded ? "collapse" : "expand")")
            .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                Haptics.light()
                activeSheet = .addHabit
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new habit")
            // Raise the + button above the disclosure button so any edge
            // taps near the seam resolve to "add" rather than "collapse" —
            // the disclosure is recoverable, an accidental sheet open is not.
            .zIndex(1)
        }
    }

    /// VoiceOver-friendly label for the habits header — strips the middle-dot
    /// separator so VO reads "Habits, 3 to do" cleanly instead of stumbling
    /// on the "·" glyph.
    private var habitsHeaderAccessibilityLabel: String {
        let todo = habitsToDoToday.count
        let done = habitsDoneToday.count
        if todo == 0 && done > 0 { return "Habits, all done today" }
        if todo == 0 { return "Habits" }
        return "Habits, \(todo) to do"
    }

    /// Title string for the habits header. Surfaces "N to do" so users can
    /// see progress at a glance without expanding the card, and says "all
    /// done" when everything is checked off for a bit of end-of-day dopamine.
    private var habitsHeaderTitle: String {
        let todo = habitsToDoToday.count
        let done = habitsDoneToday.count
        if todo == 0 && done > 0 { return "Habits · all done" }
        if todo == 0 { return "Habits" }
        return "Habits · \(todo) to do"
    }

    // MARK: - Habits Card (auto-curated)

    private var habitsCard: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let todo = habitsToDoToday
        let done = habitsDoneToday

        return VStack(spacing: 10) {
            // "Needs attention" — incomplete habits, capped at 3. Cap keeps
            // Home's visual weight stable regardless of how many habits the
            // user has defined; overflow spills into the HabitsView sheet.
            ForEach(Array(todo.prefix(3)), id: \.id) { habit in
                HabitRow(habit: habit, isDone: false, today: today, onFlightLaunch: flightLaunchHandler)
            }

            if todo.count > 3 {
                Button {
                    Haptics.light()
                    activeSheet = .habits
                } label: {
                    HStack {
                        Text("+\(todo.count - 3) more to do")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // "Done today" — collapsed by default into a single chip, expands
            // inline on tap so the completed list stays available without
            // padding out the main view.
            if !done.isEmpty {
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingDoneHabits.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.completionGreen)
                        Text("\(done.count) done today")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.textMuted)
                            .rotationEffect(.degrees(showingDoneHabits ? 90 : 0))
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showingDoneHabits {
                    ForEach(Array(done.prefix(5)), id: \.id) { habit in
                        HabitRow(habit: habit, isDone: true, today: today, onFlightLaunch: flightLaunchHandler)
                    }
                    if done.count > 5 {
                        Button {
                            Haptics.light()
                            activeSheet = .habits
                        } label: {
                            HStack {
                                // Spelling out the overflow count here so the
                                // 5 rows visible here don't contradict the "N
                                // done today" chip above (e.g. 7 done → only
                                // 5 visible → "+2 more completed").
                                Text("+\(done.count - 5) more completed")
                                    .font(AppFonts.caption(11))
                                    .foregroundColor(AppColors.accent)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Footer: single entry into the full HabitsView sheet. Replaces
            // the old header-mounted "See all" link so the header stays
            // focused on the toggle/add actions.
            Button {
                Haptics.light()
                activeSheet = .habits
            } label: {
                HStack(spacing: 4) {
                    Spacer()
                    Text("See all habits")
                        .font(AppFonts.caption(12))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(AppColors.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
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
            ScrollView {
                VStack(spacing: 16) {
                    Text("Reschedule \"\(task.title)\"")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    // Quick buttons — wrap for large Dynamic Type
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            quickRescheduleButton("Tomorrow", daysFromNow: 1, task: task)
                            quickRescheduleButton("In 3 days", daysFromNow: 3, task: task)
                            quickRescheduleButton("Next week", daysFromNow: 7, task: task)
                        }
                        VStack(spacing: 8) {
                            quickRescheduleButton("Tomorrow", daysFromNow: 1, task: task)
                            quickRescheduleButton("In 3 days", daysFromNow: 3, task: task)
                            quickRescheduleButton("Next week", daysFromNow: 7, task: task)
                        }
                    }

                    Divider()

                    DatePicker("Pick a date and time", selection: $rescheduleDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(AppColors.accent)

                    Button {
                        Haptics.success()
                        taskManager?.rescheduleTask(task, to: rescheduleDate)
                        activeSheet = nil
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Balance snapshot helper

    /// Bundles the three pieces of balance data Home's body uses so they can
    /// be computed once per evaluation instead of three times (old form
    /// called `weeklyScores()` twice through `harmonyScore()` and again
    /// directly). The `empty` singleton is used on day-0 since the Balance
    /// Pulse card isn't rendered there — skipping the work is free.
    private struct HomeBalanceSnapshot {
        let scores: [LifeDimension: Double]
        let harmony: Int
        let stage: HarmonyStage
        let hasData: Bool
        let todayFill: [LifeDimension: Double]
        let yesterdayTick: [LifeDimension: Double?]
        let todayPoints: [LifeDimension: Double]
        let dailyTarget: Int

        static let empty = HomeBalanceSnapshot(
            scores: [:],
            harmony: 30,
            stage: .resting,
            hasData: false,
            todayFill: [:],
            yesterdayTick: [:],
            todayPoints: [:],
            dailyTarget: 4
        )
    }

    private func quickRescheduleButton(_ label: String, daysFromNow: Int, task: TaskItem) -> some View {
        Button {
            Haptics.light()
            // TaskManager.composeDate handles the DST spring-forward case
            // where the original hour doesn't exist on the target day.
            let target = Calendar.current.safeDate(byAdding: .day, value: daysFromNow, to: Date())
            let composed = TaskManager.composeDate(targetDay: target, preservingTimeFrom: task.date)
            taskManager?.rescheduleTask(task, to: composed)
            activeSheet = nil
        } label: {
            Text(label)
                .font(AppFonts.label(13))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(AppColors.accentLight)
                .cornerRadius(12)
        }
        .buttonStyle(.scale)
    }
}

// MARK: - HabitRow
//
// Extracted from HomeView so each row can hold its own pulse state. Mirrors
// TaskCard's completion-pulse pattern: dimension-coloured tint blooms behind
// the row on forward completion, fades after ~1s. Same rationale — the 22pt
// checkbox alone is easy to miss, and the Balance bar pulse is offscreen
// unless Life Balance is expanded.
private struct HabitRow: View {
    let habit: HabitItem
    let isDone: Bool
    let today: Date
    /// Parallel to TaskCard's `onFlightLaunch` — Home hands the checkbox
    /// centre + primary dimension off to `ParticleAnimator` so a wave (or
    /// particle) launches from the habit row the same way tasks do. Nil in
    /// hosts without a flight destination (the HabitsView sheet, previews).
    var onFlightLaunch: ((CGPoint, LifeDimension) -> Void)? = nil

    @Environment(\.habitManager) private var habitManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulseOpacity: Double = 0
    @State private var pulseTask: Task<Void, Never>?
    /// Latest checkbox centre in the particle coord space. Mirrors TaskCard.
    @State private var checkboxCenter: CGPoint = .zero

    private var pulseColor: Color {
        // BUG-02 fix: mirror TaskCard. All-practical habits used to pulse
        // green — same colour as Body — which was a lie. Fall back to the
        // habit's first dimension colour (practical = blue-grey) so the
        // user can trust that pulse colour = the dimension that actually
        // moved. `completionGreen` stays only as a last resort for habits
        // with no dimensions at all (shouldn't exist in normal data).
        (habit.dimensions.primaryScored ?? habit.dimensions.first)?.color
            ?? AppColors.completionGreen
    }

    /// VO label for the completion button. Mirrors TaskCard's
    /// `completionAccessibilityLabel` so habits and tasks announce in the
    /// same shape — dimension first (since the visual dot conveying it is
    /// hidden from VO), then the action, then the streak so users know what
    /// they're protecting before they tap.
    private var completionAccessibilityLabel: String {
        let action = isDone ? "Mark \(habit.title) incomplete" : "Complete \(habit.title)"
        let dimPart = habit.dimensions.primaryScored.map { "\($0.shortLabel) habit. " } ?? ""
        let streak = habit.currentStreak()
        let streakPart = streak > 0 ? " Streak \(streak)." : ""
        return "\(dimPart)\(action).\(streakPart)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                // BUG-02 (earlier): bail before any feedback if no manager —
                // user shouldn't get celebratory haptic for a no-op save.
                guard let habitManager else { return }
                // BUG-03 (earlier): read the model's truth, not the
                // parent-passed Bool (which can be stale across rebuilds and
                // disagrees with the throttle in
                // `HabitManager.toggleCompletion`).
                //
                // BUG-01 + BUG-08 fix: haptic was firing unconditionally,
                // so double-tapping inside HabitManager's 250ms throttle
                // produced two "success" haptics for one real toggle — the
                // second tap was a no-op but vibrated like a success.
                // Restructured so ALL feedback (haptic + pulse + flight)
                // is gated on the actual pre/post-toggle state delta. A
                // throttled tap now produces no haptic, no pulse, no flight
                // — fully consistent. Uncomplete gets a lighter haptic and
                // no celebratory visuals (forward-only celebration).
                let wasCompleted = habit.isCompletedOn(today)
                withAnimation(.spring(response: 0.3)) {
                    // Routed through HabitManager so the BalancePulse bus
                    // fires and the Compass bar animates — the direct
                    // `habit.toggleCompletion + safeSave` path skipped both.
                    habitManager.toggleCompletion(habit, for: today)
                }
                let isNowCompleted = habit.isCompletedOn(today)
                if !wasCompleted && isNowCompleted {
                    Haptics.success()
                    firePulse()
                    launchFlightIfPossible()
                } else if wasCompleted && !isNowCompleted {
                    Haptics.light()
                }
                // else: throttle dropped the tap — no feedback, matches the
                // manager's silent no-op contract.
            } label: {
                ZStack {
                    Circle()
                        .stroke(isDone ? AppColors.completionGreen : habit.effectiveColor, lineWidth: 2)
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
                // Mirror TaskCard: only capture the checkbox centre when
                // Home supplied a flight callback. Outside Home (the
                // HabitsView sheet) the named coord space doesn't exist,
                // and capturing global-space coords would poison
                // `checkboxCenter` with numbers that can't be used for a
                // particle anyway.
                .background(
                    Group {
                        if onFlightLaunch != nil {
                            GeometryReader { proxy in
                                let f = proxy.frame(in: .named(particleCoordinateSpace))
                                Color.clear.preference(
                                    key: HabitCheckboxFrameKey.self,
                                    value: CGPoint(x: f.midX, y: f.midY)
                                )
                            }
                        } else {
                            Color.clear
                        }
                    }
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completionAccessibilityLabel)

            Text(habit.icon)
                .font(.system(size: 16))
                .accessibilityHidden(true)

            // Dimension dot + title. Mirrors TaskCard so habits and tasks
            // read identically at a glance — the dot is the pre-completion
            // hint of which Compass bar this habit will feed.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let dim = habit.dimensions.primaryScored {
                    Circle()
                        .fill(dim.color)
                        .frame(width: 7, height: 7)
                        .alignmentGuide(.firstTextBaseline) { d in d.height - 1 }
                        .accessibilityHidden(true)
                }
                Text(habit.title)
                    .font(AppFonts.body(14))
                    .foregroundColor(isDone ? AppColors.textMuted : AppColors.textPrimary)
                    .strikethrough(isDone)
            }
            // Title is announced via the checkbox button's label; suppress
            // the duplicate VO read here.
            .accessibilityHidden(true)
            Spacer()

            let streak = habit.currentStreak()
            if streak > 0 {
                Text("\(streak)🔥")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.accentWarm)
                    // Streak count is already in the button label; the bare
                    // emoji ("3 flame") would otherwise announce twice.
                    .accessibilityHidden(true)
            }
        }
        // BUG-10: keep vertical padding tight so the pulse rectangles don't
        // visually kiss at AX3 — VStack(spacing: 10) outside gives 6pt gap
        // with 2pt padding here, vs 2pt gap with the prior 4pt padding.
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(pulseColor.opacity(0.16 * pulseOpacity))
        )
        // BUG-05: cancel any in-flight envelope when the row leaves the
        // hierarchy (collapse, sheet dismiss, scroll-recycle in a hosted
        // LazyVStack). Without this, a recycled view can mount with leftover
        // pulseOpacity > 0.
        .onDisappear {
            pulseTask?.cancel()
            pulseOpacity = 0
        }
        .onPreferenceChange(HabitCheckboxFrameKey.self) { center in
            // BUG-10 fix: mirror the 2pt threshold used by
            // `dimensionBarCenters`. Without it, each scroll frame publishes
            // a sub-pixel-different centre which reassigns @State and forces
            // unnecessary body re-evals — measurable drag on longer habit
            // lists.
            guard center != checkboxCenter else { return }
            if abs(center.x - checkboxCenter.x) > 2 || abs(center.y - checkboxCenter.y) > 2 || checkboxCenter == .zero {
                checkboxCenter = center
            }
        }
    }

    /// Mirrors TaskCard.launchFlightIfPossible. Only fires when:
    ///   - the parent supplied a flight callback (Home wires one, the
    ///     HabitsView sheet doesn't)
    ///   - the habit has at least one scored dimension (practical-only
    ///     habits don't feed a balance bar, so there's no visual target)
    ///   - the checkbox centre has been captured in the particle coord space
    private func launchFlightIfPossible() {
        guard let onFlightLaunch,
              let dim = habit.dimensions.primaryScored,
              checkboxCenter != .zero else { return }
        onFlightLaunch(checkboxCenter, dim)
    }

    /// Same pulse envelope as TaskCard.firePulse so habit + task completions
    /// feel identical. See TaskCard for the rationale on Reduce Motion timing.
    private func firePulse() {
        pulseTask?.cancel()
        pulseTask = Task { @MainActor in
            let bloom: Double = reduceMotion ? 0.25 : 0.15
            let fade: Double = reduceMotion ? 0.7 : 0.6
            let holdMs: Int = 250

            withAnimation(.easeOut(duration: bloom)) { pulseOpacity = 1.0 }
            try? await Task.sleep(for: .milliseconds(Int(bloom * 1000) + holdMs))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fade)) { pulseOpacity = 0 }
        }
    }
}

/// Per-row preference key carrying the habit checkbox centre up to the
/// HabitRow's own `onPreferenceChange`. Scoped to the individual row so
/// each row captures its own button position. Parallel to TaskCard's
/// `TaskCheckboxFrameKey` — kept separate so Task and Habit rows in the
/// same List don't stomp on each other's preference values.
private struct HabitCheckboxFrameKey: PreferenceKey {
    static var defaultValue: CGPoint { .zero }
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
