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

    /// No-op as of the security audit: the Anthropic key is no longer
    /// broadcast over WCSession. The iPhone writes the key into the
    /// `group.com.myaissistant.shared` Keychain access group via
    /// `KeychainService` (already configured), and the Watch reads the
    /// same record directly. Keeping this entry point + signature so any
    /// existing callers ("on key change, sync to Watch") still link;
    /// the Watch-side `loadAPIKeyFromSharedKeychain()` is now the source
    /// of truth.
    ///
    /// Why removed: the previous implementation pushed the API key into
    /// `WCSession.updateApplicationContext` and `sendMessage`. Both land
    /// in the WC sandbox (a plist), not Keychain — readable from a
    /// paired-computer backup of an unlocked-once device. Shared
    /// Keychain stays inside the Keychain encryption boundary.
    func syncAPIKey() {
        // Intentionally empty — see header.
        // Push only the textSize hint, which is non-secret.
        guard let session, isActivated, session.isPaired, session.isWatchAppInstalled else { return }
        var context = session.applicationContext
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

        // Read-modify-write so non-payload keys (e.g. `textSize`) set by
        // sibling methods survive this push. We deliberately do NOT add
        // the Anthropic API key here — see `syncAPIKey()` header. The
        // Watch reads the key from the shared App-Group Keychain
        // directly, which keeps it inside the Keychain encryption
        // boundary instead of WC's plist sandbox.
        var context = session.applicationContext
        for (key, value) in data.toDictionary() {
            context[key] = value
        }
        // Strip any stale `apiKey` left over from prior builds — it can
        // linger in the WC applicationContext indefinitely until the next
        // overwrite.
        context.removeValue(forKey: "apiKey")
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

    /// Handle Watch requesting a fresh schedule update, toggling a task, or adding a task.
    /// All string fields from the Watch payload are length-bounded and the
    /// `addTask.title` is run through the prompt sanitizer before persisting,
    /// so a future watch-side compromise can't push a forged action-tag glyph
    /// or a megabyte of text into our SwiftData store.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "scheduleUpdate" {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchRequestedUpdate, object: nil)
            }
        }
        if let taskID = message["toggleTask"] as? String, Self.isValidTaskID(taskID) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if message["addTask"] as? Bool == true,
           let validated = Self.validatedAddTaskPayload(message) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: validated)
            }
        }
        if message["quickCheckIn"] as? Bool == true,
           let validated = Self.validatedQuickCheckInPayload(message) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: validated)
            }
        }
        if let taskID = message["deleteTask"] as? String, Self.isValidTaskID(taskID) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchDeletedTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
    }

    // MARK: - WC payload validation

    /// Task IDs in our schema are UUIDs (36 chars) or `google:<id>` —
    /// neither exceeds 128 chars. Reject anything outside that band so a
    /// hostile string can't cascade into a `#Predicate` or NotificationCenter
    /// userInfo of arbitrary size.
    nonisolated static func isValidTaskID(_ id: String) -> Bool {
        (1...128).contains(id.count)
    }

    nonisolated static func validatedAddTaskPayload(_ raw: [String: Any]) -> [String: Any]? {
        guard let title = raw["title"] as? String, !title.isEmpty,
              title.count <= 200,
              let priority = raw["priority"] as? String, priority.count <= 16,
              let date = raw["date"] as? TimeInterval else { return nil }

        // Sanitize title with the same logic used app-wide so a Watch-relayed
        // title can't fabricate a `[[CREATE_EVENT:…]]` glyph that later flows
        // into an LLM prompt.
        let safeTitle = title
            .replacingOccurrences(of: "[[", with: "⟦")
            .replacingOccurrences(of: "]]", with: "⟧")
            .replacingOccurrences(of: "|", with: "∣")

        var validated: [String: Any] = [
            "addTask": true,
            "title": safeTitle,
            "priority": priority,
            "date": date,
            "hasTime": (raw["hasTime"] as? Bool) ?? false
        ]
        if let dims = raw["dimensions"] as? String, dims.count <= 64 {
            validated["dimensions"] = dims
        }
        return validated
    }

    nonisolated static func validatedQuickCheckInPayload(_ raw: [String: Any]) -> [String: Any]? {
        guard let mood = raw["mood"] as? Int, (0...10).contains(mood),
              let energy = raw["energy"] as? Int, (0...10).contains(energy),
              let slot = raw["timeSlot"] as? String, slot.count <= 32 else { return nil }
        return [
            "quickCheckIn": true,
            "mood": mood,
            "energy": energy,
            "timeSlot": slot
        ]
    }

    /// Handle app-context pushes (latest-state, overwriting). Watch doesn't
    /// push contexts today, but implementing this means a future Watch-side
    /// updateApplicationContext won't vanish silently — it'll route through
    /// the same message handlers below.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let taskID = applicationContext["toggleTask"] as? String, Self.isValidTaskID(taskID) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if applicationContext["quickCheckIn"] as? Bool == true,
           let validated = Self.validatedQuickCheckInPayload(applicationContext) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: validated)
            }
        }
    }

    /// Handle queued messages sent via transferUserInfo (when iPhone wasn't reachable)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let taskID = userInfo["toggleTask"] as? String, Self.isValidTaskID(taskID) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchToggledTask, object: nil, userInfo: ["taskID": taskID])
            }
        }
        if userInfo["addTask"] as? Bool == true,
           let validated = Self.validatedAddTaskPayload(userInfo) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchAddedTask, object: nil, userInfo: validated)
            }
        }
        if userInfo["quickCheckIn"] as? Bool == true,
           let validated = Self.validatedQuickCheckInPayload(userInfo) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .watchQuickCheckIn, object: nil, userInfo: validated)
            }
        }
        if let taskID = userInfo["deleteTask"] as? String, Self.isValidTaskID(taskID) {
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
