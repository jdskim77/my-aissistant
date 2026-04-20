import Foundation
import Observation
import WatchConnectivity
import os.log

// MARK: - Engine / Reusable (with Thrivn-specific surface flagged below)
//
// iPhone-side WatchConnectivity coordinator. Handles activation, pending-sync
// queuing until the session is ready, message vs applicationContext routing,
// and delegate plumbing for incoming Watch actions (task toggles, quick
// check-ins, etc.).
//
// REUSABLE (keep in fork):
//   - Session activation + activation-pending queue
//   - syncAPIKey pattern (Keychain → Watch)
//   - updateApplicationContext usage with latest-value-wins semantics
//   - Delegate forwarding via NotificationCenter.Name extensions
//
// ⚠️ THRIVN-SPECIFIC — REPLACE IN FORK:
//   - `syncSchedule(...)` signature takes `compassScores` as a named tuple
//     (body/mind/heart/spirit). A fork should replace with a generic
//     dictionary, e.g. `dimensionScores: [String: Double]?`, or take a
//     fully-formed `WatchScheduleData` from the caller.
//   - `completedCheckIns: [String]?` parameter ties to the Thrivn 4-slot
//     daily check-in model (see `CheckInTime`).
//   - `anthropicAPIKey()` in `syncAPIKey()` assumes Thrivn's provider layout.
//
// Dependencies: WatchConnectivity, KeychainService, TextSizeManager, and
// the Thrivn `TaskItem` model (reusable as a CodableTask shape).
// Watch-compatible: no (iOS-side). The Watch counterpart is
// `WatchConnectivityManager` in the Watch target.

/// Manages iPhone → Watch data sync via WatchConnectivity.
/// Sends schedule snapshots to the Watch app whenever tasks change.
@Observable @MainActor
final class WatchSyncManager: NSObject {
    static let shared = WatchSyncManager()
    private var session: WCSession?
    private var isActivated = false
    /// Pending sync to fire once session activates
    private var pendingSync: (() -> Void)?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    /// Send API key to Watch so it can make direct Claude API calls.
    func syncAPIKey() {
        guard let session else { return }
        guard isActivated, session.isPaired, session.isWatchAppInstalled else { return }
        let keychain = KeychainService()
        guard let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty else { return }
        let message = ["apiKey": apiKey]
        // Use both channels to ensure delivery
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        }
        // Also include in application context for when Watch isn't reachable
        var context = session.applicationContext
        context["apiKey"] = apiKey
        context["textSize"] = TextSizeManager.shared.selectedSize.rawValue
        try? session.updateApplicationContext(context)
    }

    /// Send current schedule to Watch. Call after any task mutation.
    func syncSchedule(
        tasks: [TaskItem],
        streak: Int,
        quoteText: String?,
        quoteAuthor: String?,
        compassScores: (body: Double, mind: Double, heart: Double, spirit: Double)? = nil,
        userName: String? = nil,
        aiInsight: String? = nil,
        completedCheckIns: [String]? = nil
    ) {
        guard let session else { return }

        // If session hasn't activated yet, queue this sync for later
        guard isActivated else {
            pendingSync = { [weak self] in
                self?.syncSchedule(
                    tasks: tasks, streak: streak, quoteText: quoteText, quoteAuthor: quoteAuthor,
                    compassScores: compassScores, userName: userName, aiInsight: aiInsight,
                    completedCheckIns: completedCheckIns
                )
            }
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        // `safeDate` returns the original date on failure, which would
        // collapse the [dayStart, dayEnd) filter range to empty and silently
        // ship an empty payload. Fall back to a literal 24h offset so we
        // always include today's tasks even on degenerate calendar arithmetic.
        let calendarDayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)
        let dayEnd = calendarDayEnd > dayStart
            ? calendarDayEnd
            : dayStart.addingTimeInterval(86400)

        let todayTasks = tasks.filter { $0.date >= dayStart && $0.date < dayEnd }
            .sorted { $0.date < $1.date }

        let watchTasks = todayTasks.map { task in
            WatchScheduleData.WatchTask(
                id: task.id,
                title: task.title,
                date: task.date,
                priorityRaw: task.priorityRaw,
                categoryRaw: task.categoryRaw,
                done: task.done,
                isCalendarEvent: task.externalCalendarID != nil,
                recurrenceRaw: task.recurrenceRaw,
                dimensionsRaw: task.dimensionRaw
            )
        }

        // Which slot is the user currently in? Single source of truth is
        // CheckInTime.slot(forHour:) — Watch and iOS must agree on the label.
        let hour = calendar.component(.hour, from: Date())
        let nextCheckIn: String? = CheckInTime.slot(forHour: hour).rawValue

        let data = WatchScheduleData(
            tasks: watchTasks,
            streakDays: streak,
            completedToday: todayTasks.filter(\.done).count,
            totalToday: todayTasks.count,
            quoteText: quoteText,
            quoteAuthor: quoteAuthor,
            nextCheckIn: nextCheckIn,
            updatedAt: Date(),
            bodyScore: compassScores?.body,
            mindScore: compassScores?.mind,
            heartScore: compassScores?.heart,
            spiritScore: compassScores?.spirit,
            userName: userName,
            aiInsight: aiInsight,
            completedCheckIns: completedCheckIns
        )

        // Read-modify-write so any keys set by `syncAPIKey` (or future
        // sibling methods) survive this push. Starting from
        // `data.toDictionary()` would silently drop unrelated keys —
        // currently safe because we re-add apiKey + textSize below, but
        // fragile as more keys join the context.
        var context = session.applicationContext
        for (key, value) in data.toDictionary() {
            context[key] = value
        }
        let keychain = KeychainService()
        if let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty {
            context["apiKey"] = apiKey
        }
        context["textSize"] = TextSizeManager.shared.selectedSize.rawValue
        try? session.updateApplicationContext(context)
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            Task { @MainActor in
                self.isActivated = true
                self.pendingSync?()
                self.pendingSync = nil
            }
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Handle Watch requesting a fresh schedule update, toggling a task, or adding a task
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "scheduleUpdate" {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchRequestedUpdate, object: nil)
            }
        }
        if let taskID = message["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if message["addTask"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: message)
            }
        }
        if message["quickCheckIn"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: message)
            }
        }
        if let taskID = message["deleteTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchDeletedTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }

    /// Handle app-context pushes (latest-state, overwriting). Watch doesn't
    /// push contexts today, but implementing this means a future Watch-side
    /// updateApplicationContext won't vanish silently — it'll route through
    /// the same message handlers below.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let taskID = applicationContext["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if applicationContext["quickCheckIn"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: applicationContext)
            }
        }
    }

    /// Handle queued messages sent via transferUserInfo (when iPhone wasn't reachable)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let taskID = userInfo["toggleTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if userInfo["addTask"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: userInfo)
            }
        }
        if userInfo["quickCheckIn"] as? Bool == true {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: userInfo)
            }
        }
        if let taskID = userInfo["deleteTask"] as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchDeletedTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }
}

extension Notification.Name {
    static let watchRequestedUpdate = Notification.Name("watchRequestedUpdate")
    static let watchToggledTask = Notification.Name("watchToggledTask")
    static let watchAddedTask = Notification.Name("watchAddedTask")
    static let watchDeletedTask = Notification.Name("watchDeletedTask")
    static let watchQuickCheckIn = Notification.Name("watchQuickCheckIn")
    /// Fired after a habit has been toggled completed OUTSIDE HabitManager
    /// (Siri intent, widget, notification action). The main app observer
    /// routes it back through `HabitManager.announceCompletion(habitID:)`
    /// so the Compass pulse + cache invalidation still happen.
    static let habitToggledExternally = Notification.Name("habitToggledExternally")
}
