import BackgroundTasks
import SwiftData

/// Registers and handles background tasks for daily snapshots, weekly AI reviews, and calendar sync.
@MainActor
final class BackgroundTaskManager {
    static let dailySnapshotID = "com.myaissistant.daily-snapshot"
    static let weeklyReviewID = "com.myaissistant.weekly-review"
    static let calendarSyncID = "com.myaissistant.calendar-sync"

    private let modelContext: ModelContext
    private let patternEngine: PatternEngine
    private let calendarSyncManager: CalendarSyncManager

    init(modelContext: ModelContext, patternEngine: PatternEngine, calendarSyncManager: CalendarSyncManager) {
        self.modelContext = modelContext
        self.patternEngine = patternEngine
        self.calendarSyncManager = calendarSyncManager
    }

    // MARK: - Registration

    func registerAll() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailySnapshotID,
            using: nil
        ) { task in
            Task { @MainActor in
                await self.handleDailySnapshot(task as! BGProcessingTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.weeklyReviewID,
            using: nil
        ) { task in
            Task { @MainActor in
                await self.handleWeeklyReview(task as! BGProcessingTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.calendarSyncID,
            using: nil
        ) { task in
            Task { @MainActor in
                await self.handleCalendarSync(task as! BGAppRefreshTask)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleDailySnapshot() {
        let request = BGProcessingTaskRequest(identifier: Self.dailySnapshotID)
        // Run after midnight
        let calendar = Calendar.current
        var nextMidnight = calendar.startOfDay(for: Date())
        nextMidnight = calendar.date(byAdding: .day, value: 1, to: nextMidnight)!
        request.earliestBeginDate = nextMidnight
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleWeeklyReview() {
        let request = BGProcessingTaskRequest(identifier: Self.weeklyReviewID)
        // Schedule for Sunday 9 PM
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = AppConstants.weeklyReviewDay
        components.hour = AppConstants.weeklyReviewHour
        if let nextSunday = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) {
            request.earliestBeginDate = nextSunday
        }
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleCalendarSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.calendarSyncID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private func handleDailySnapshot(_ task: BGProcessingTask) async {
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        await createDailySnapshot()
        scheduleDailySnapshot() // Reschedule for tomorrow
        task.setTaskCompleted(success: true)
    }

    private func handleWeeklyReview(_ task: BGProcessingTask) async {
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // Use free tier for background review (conservative); Pro users get better model
        await patternEngine.generateWeeklyReview(tier: .free)
        scheduleWeeklyReview() // Reschedule for next Sunday
        task.setTaskCompleted(success: true)
    }

    private func handleCalendarSync(_ task: BGAppRefreshTask) async {
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        await calendarSyncManager.syncAppleCalendar()
        scheduleCalendarSync() // Reschedule
        task.setTaskCompleted(success: true)
    }

    // MARK: - Daily Snapshot Creation

    private func createDailySnapshot() async {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let today = calendar.startOfDay(for: Date())

        // Tasks
        let totalDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today }
        )
        let doneDescriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today && $0.done == true }
        )
        let tasksTotal = (try? modelContext.fetchCount(totalDescriptor)) ?? 0
        let tasksCompleted = (try? modelContext.fetchCount(doneDescriptor)) ?? 0

        // Check-ins
        let checkInDescriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today && $0.completed == true }
        )
        let checkIns = (try? modelContext.fetch(checkInDescriptor)) ?? []
        let checkInsCompleted = checkIns.count
        let moods = checkIns.compactMap { $0.mood }
        let averageMood = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)

        let snapshot = DailySnapshot(
            date: yesterday,
            tasksTotal: tasksTotal,
            tasksCompleted: tasksCompleted,
            checkInsCompleted: checkInsCompleted,
            averageMood: averageMood,
            streakCount: patternEngine.currentStreak()
        )

        modelContext.insert(snapshot)
        try? modelContext.save()
    }
}
