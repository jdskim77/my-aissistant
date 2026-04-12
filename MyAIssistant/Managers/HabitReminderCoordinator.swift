import Foundation
import Observation
import SwiftData
import UserNotifications
import os.log

/// Coordinates intelligent habit reminders by combining:
/// - HabitItem completion history (what's due, what's done)
/// - PatternEngine (learned optimal times)
/// - TaskManager (schedule clearance)
/// - NotificationManager (delivery)
///
/// Runs daily (called from app .task block) and decides for each habit:
/// 1. Is it a target day? (skip if not)
/// 2. Is it already completed? (skip if yes)
/// 3. What's the optimal reminder time? (learned > configured > default)
/// 4. Is the user's schedule clear at that time? (prefer gaps)
/// 5. Has the user ignored 3+ consecutive reminders? (backoff)
@Observable @MainActor
final class HabitReminderCoordinator {
    private let modelContext: ModelContext

    var patternEngine: PatternEngine?
    var taskManager: TaskManager?
    var notificationManager: NotificationManager?

    /// Tracks consecutive dismissals per habit for backoff.
    /// Stored in UserDefaults as [habitID: count].
    private static let dismissalKey = "habitReminder_dismissals"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Daily Coordination

    /// Run once daily (from app .task block). Evaluates each active habit
    /// and schedules smart one-shot reminders for today.
    func coordinateToday() {
        guard let nm = notificationManager else { return }

        var descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 30
        let habits = (try? modelContext.fetch(descriptor)) ?? []

        let today = Date()
        let todayTasks = taskManager?.todayTasks() ?? []
        let dismissals = loadDismissals()

        for habit in habits {
            // 1. Is it a target day?
            guard habit.targetDays.appliesTo(date: today) else { continue }

            // 2. Already completed today?
            guard !habit.isCompletedOn(today) else { continue }

            // 3. Streak-adaptive: established habits (22+ day streak) only
            //    get reminded on missed days, not every day.
            let streak = habit.currentStreak()
            if streak >= 22 {
                // Ingrained habit — no reminders needed unless they've missed recently
                continue
            }

            // 4. Backed off? (3+ consecutive ignored reminders)
            let dismissed = dismissals[habit.id] ?? 0
            guard dismissed < 3 else { continue }

            // 4. Determine optimal time
            let reminderTime = optimalReminderTime(for: habit, today: today, tasks: todayTasks)

            // 5. Only schedule if the time is in the future
            guard reminderTime > today else { continue }

            // 6. Schedule a one-shot smart reminder
            scheduleSmartReminder(habit: habit, at: reminderTime, nm: nm, streak: habit.currentStreak())
        }
    }

    // MARK: - Optimal Time Detection

    /// Determines the best time to remind for this habit:
    /// 1. Learned time from PatternEngine (if habit title matches an activity pattern)
    /// 2. Configured reminder time on the habit
    /// 3. Default: evening (7 PM)
    private func optimalReminderTime(for habit: HabitItem, today: Date, tasks: [TaskItem]) -> Date {
        let calendar = Calendar.current

        // 1. Check PatternEngine for learned timing
        if let pe = patternEngine {
            let bestTimes = pe.bestTimePerCategory()
            // Match habit title keywords against activity categories
            let lower = habit.title.lowercased()
            for (category, hour) in bestTimes {
                if lower.contains(category.lowercased()) || category.lowercased().contains(lower) {
                    if let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today) {
                        // Check if schedule is clear around this time (±30 min)
                        if isScheduleClear(at: time, tasks: tasks) {
                            return time
                        }
                    }
                }
            }
        }

        // 2. Use configured reminder time
        if let hour = habit.reminderHour, let minute = habit.reminderMinute {
            if let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) {
                return time
            }
        }

        // 3. Default: 7 PM (evening, likely free time)
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: today) ?? today
    }

    /// Check if the user has no tasks within ±30 minutes of the proposed time.
    private func isScheduleClear(at time: Date, tasks: [TaskItem]) -> Bool {
        let window: TimeInterval = 30 * 60 // 30 minutes
        let start = time.addingTimeInterval(-window)
        let end = time.addingTimeInterval(window)
        return !tasks.contains { $0.date >= start && $0.date <= end && !$0.done }
    }

    // MARK: - Smart Reminder Scheduling

    private func scheduleSmartReminder(habit: HabitItem, at time: Date, nm: NotificationManager, streak: Int) {
        let center = UNUserNotificationCenter.current()
        let identifier = "smarthabit-\(habit.id)"

        // Remove any existing smart reminder for this habit
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "\(habit.icon) \(habit.title)"
        content.body = smartReminderBody(habit: habit, streak: streak)
        content.sound = .default
        content.categoryIdentifier = "HABIT"
        content.userInfo = ["habitID": habit.id]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: time
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
        AppLogger.notifications.info("Smart habit reminder: \(habit.title, privacy: .public) at \(components.hour ?? 0, privacy: .public):\(components.minute ?? 0, privacy: .public)")
    }

    private func smartReminderBody(habit: HabitItem, streak: Int) -> String {
        let daysSince = daysSinceLastCompletion(habit)

        if streak >= 7 {
            return "\(streak)-day streak. Keep it going."
        } else if let days = daysSince, days >= 4 {
            return "It's been \(days) days. Even a small effort counts."
        } else if let days = daysSince, days >= 2 {
            return "\(days) days since your last time. Good moment to get back to it."
        } else {
            return "Your schedule looks clear — good time for this."
        }
    }

    private func daysSinceLastCompletion(_ habit: HabitItem) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 1...90 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { break }
            if habit.isCompletedOn(date) { return offset }
        }
        return nil
    }

    // MARK: - Dismissal Tracking (Backoff)

    /// Call when a user dismisses (ignores) a habit notification.
    func recordDismissal(habitID: String) {
        var dismissals = loadDismissals()
        dismissals[habitID, default: 0] += 1
        saveDismissals(dismissals)
    }

    /// Call when a user completes a habit — resets the dismissal count.
    func resetDismissal(habitID: String) {
        var dismissals = loadDismissals()
        dismissals.removeValue(forKey: habitID)
        saveDismissals(dismissals)
    }

    private func loadDismissals() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: Self.dismissalKey) as? [String: Int]) ?? [:]
    }

    private func saveDismissals(_ dismissals: [String: Int]) {
        UserDefaults.standard.set(dismissals, forKey: Self.dismissalKey)
    }

    // MARK: - Habits Due Today (for UI)

    /// Returns active habits that are due today but not yet completed.
    func habitsDueToday() -> [HabitItem] {
        var descriptor = FetchDescriptor<HabitItem>(
            predicate: #Predicate { $0.archivedAt == nil }
        )
        descriptor.fetchLimit = 30
        let habits = (try? modelContext.fetch(descriptor)) ?? []
        let today = Date()
        return habits.filter { $0.targetDays.appliesTo(date: today) && !$0.isCompletedOn(today) }
    }
}
