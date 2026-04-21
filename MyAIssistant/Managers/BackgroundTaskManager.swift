import BackgroundTasks
import Foundation
import SwiftData

// MARK: - Engine / Reusable (with Thrivn-specific task IDs)
//
// BGTaskScheduler registration + handler scaffolding for daily/weekly
// background work. The PATTERN is generic; the specific task IDs and what
// they do (snapshot, AI review, calendar sync) are app-specific.
//
// Reusable: pattern yes, IDs and handlers no.
// Dependencies: BackgroundTasks, SwiftData (for snapshot persistence).
// Watch-compatible: no (iOS-only — Watch uses WKApplicationRefreshBackgroundTask).
//
// Fork notes:
// - Replace task IDs (`com.myaissistant.*`) with your app's bundle prefix.
// - Register the same IDs in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
// - Handlers are app-specific business logic — write fresh in the fork.

/// Registers and handles background tasks for daily snapshots, weekly AI reviews, and calendar sync.
@MainActor
final class BackgroundTaskManager {
    static let dailySnapshotID = "com.myaissistant.daily-snapshot"
    static let weeklyReviewID = "com.myaissistant.weekly-review"
    static let calendarSyncID = "com.myaissistant.calendar-sync"
    static let nudgeEvaluationID = AppConstants.nudgeEvaluationBGTaskID

    private let modelContext: ModelContext
    private let patternEngine: PatternEngine
    private let calendarSyncManager: CalendarSyncManager
    private let checkInBehaviorEngine: CheckInBehaviorEngine?
    private let nudgeEngine: NudgeEngine?

    init(
        modelContext: ModelContext,
        patternEngine: PatternEngine,
        calendarSyncManager: CalendarSyncManager,
        checkInBehaviorEngine: CheckInBehaviorEngine? = nil,
        nudgeEngine: NudgeEngine? = nil
    ) {
        self.modelContext = modelContext
        self.patternEngine = patternEngine
        self.calendarSyncManager = calendarSyncManager
        self.checkInBehaviorEngine = checkInBehaviorEngine
        self.nudgeEngine = nudgeEngine
    }

    // MARK: - Registration

    func registerAll() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailySnapshotID,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let bgTask = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
                await self.handleDailySnapshot(bgTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.weeklyReviewID,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let bgTask = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
                await self.handleWeeklyReview(bgTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.calendarSyncID,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let bgTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
                await self.handleCalendarSync(bgTask)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.nudgeEvaluationID,
            using: nil
        ) { task in
            Task { @MainActor in
                guard let bgTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
                await self.handleNudgeEvaluation(bgTask)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleDailySnapshot() {
        let request = BGProcessingTaskRequest(identifier: Self.dailySnapshotID)
        // Run after midnight
        let calendar = Calendar.current
        var nextMidnight = calendar.startOfDay(for: Date())
        nextMidnight = calendar.safeDate(byAdding: .day, value: 1, to: nextMidnight)
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

    /// Early-morning evaluation (~6 AM) that pre-composes up to one nudge for
    /// the day. Phase 1 is a no-op because the engine's kill switch is on and
    /// the rule set is empty — but the BGTask still registers and reschedules
    /// so Phase 2 flips a flag instead of adding plumbing.
    func scheduleNudgeEvaluation() {
        let request = BGAppRefreshTaskRequest(identifier: Self.nudgeEvaluationID)
        // Target 6 AM tomorrow; iOS treats this as "not before" and may run later.
        let calendar = Calendar.current
        var target = calendar.startOfDay(for: Date())
        target = calendar.safeDate(byAdding: .day, value: 1, to: target)
        if let at6 = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: target) {
            request.earliestBeginDate = at6
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60 * 6)
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private func handleDailySnapshot(_ task: BGProcessingTask) async {
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        await createDailySnapshot()
        checkInBehaviorEngine?.recalculateIfNeeded()
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
        await calendarSyncManager.syncReminders()
        scheduleCalendarSync() // Reschedule
        task.setTaskCompleted(success: true)
    }

    private func handleNudgeEvaluation(_ task: BGAppRefreshTask) async {
        // BUG-07 fix: guard against double-completion. If `expirationHandler`
        // fires (system starved the task) AND the async body later resumes,
        // both paths previously called `setTaskCompleted` — Apple considers
        // double-completion a programming error. `TaskCompletionBarrier`
        // enforces once-only delivery under concurrent access.
        let barrier = TaskCompletionBarrier()
        task.expirationHandler = { barrier.complete(task: task, success: false) }

        // Phase 1: kill switch is on by default, so the engine short-circuits
        // and no nudge is composed or delivered. BGTask still reschedules.
        let ok = await nudgeEngine?.runScheduledEvaluation() ?? true
        scheduleNudgeEvaluation()
        barrier.complete(task: task, success: ok)
    }

    // MARK: - Daily Snapshot Creation

    private func createDailySnapshot() async {
        let calendar = Calendar.current
        let yesterday = calendar.safeDate(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
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

        // Dynamic window count from preferences, fallback to default 4
        let activeWindowCount = checkInBehaviorEngine?.activePreferences().count ?? 4

        let snapshot = DailySnapshot(
            date: yesterday,
            tasksTotal: tasksTotal,
            tasksCompleted: tasksCompleted,
            checkInsCompleted: checkInsCompleted,
            checkInsTotal: activeWindowCount,
            averageMood: averageMood,
            streakCount: patternEngine.currentStreak()
        )

        modelContext.insert(snapshot)
        modelContext.safeSave()
    }
}

// MARK: - Task completion barrier

/// Ensures `BGTask.setTaskCompleted(success:)` is called at most once across
/// the expiration path and the async body. `expirationHandler` may fire on an
/// internal queue concurrently with the `@MainActor` body resuming, so the
/// guard is synchronized with `NSLock`. Once completed, further calls no-op.
///
/// Scoped to the Phase 1 nudge-evaluation handler per QA finding BUG-07. The
/// three legacy handlers (daily snapshot, weekly review, calendar sync) share
/// the same double-completion risk but are intentionally left untouched in
/// this patch — they're out of scope for the Phase 1 Nudge Engine review.
final class TaskCompletionBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var isCompleted = false

    func complete(task: BGTask, success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true
        task.setTaskCompleted(success: success)
    }
}
