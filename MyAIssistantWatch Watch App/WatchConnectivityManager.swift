#if os(watchOS)
import Foundation
import WatchConnectivity
import SwiftUI
import WidgetKit
import Security

// MARK: - Engine / Reusable (with Thrivn-shaped payload type)
//
// Watch-side counterpart to iOS WatchSyncManager. Receives application
// context updates from iPhone, decodes into `WatchScheduleData`, exposes
// it to views + complications, and forwards Watch-originated actions back
// to iPhone (task toggles, quick check-ins, voice chat triggers).
//
// REUSABLE (keep in fork):
//   - Singleton + WCSessionDelegate boilerplate
//   - applicationContext receive + decode flow
//   - sendMessage paths for Watch → iPhone actions
//   - WidgetKit reload after data updates
//   - shouldOpenVoiceChat flag for Action Button intent
//
// ⚠️ THRIVN-SPECIFIC — REVISIT IN FORK:
//   - The payload type `WatchScheduleData` (see its own header — its
//     bodyScore/mindScore/heartScore/spiritScore fields are Thrivn).
//   - The "quickCheckIn" message format ties to Thrivn's check-in model.
//
// Dependencies: WatchConnectivity, WidgetKit, WatchScheduleData (shared
// payload struct), Security (for forwarded API key).
// Watch-compatible: yes (this IS the Watch target).

/// Receives schedule data from iPhone and makes it available to Watch views + complications.
@Observable
@MainActor
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    /// Singleton — used by Action Button intent and passed to views.
    static let shared = WatchConnectivityManager()

    var scheduleData: WatchScheduleData?
    var shouldOpenVoiceChat = false
    /// True once WCSession activation has completed (success or failure) OR
    /// any payload has been received. Views use this to decide between
    /// "Syncing…" and "Can't reach iPhone" — without it, we can't tell a
    /// genuinely-offline first-launch from an in-progress activation.
    var hasAttemptedSync = false
    private(set) var apiKey: String?

    override init() {
        super.init()
        loadFromCache()
        loadAPIKeyFromCache()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var todayTasks: [WatchScheduleData.WatchTask] {
        scheduleData?.tasks ?? []
    }

    var activeTasks: [WatchScheduleData.WatchTask] {
        todayTasks.filter { !$0.done }
    }

    var completedTasks: [WatchScheduleData.WatchTask] {
        todayTasks.filter(\.done)
    }

    var completionFraction: Double {
        guard let data = scheduleData, data.totalToday > 0 else { return 0 }
        return Double(data.completedToday) / Double(data.totalToday)
    }

    var upNextTask: WatchScheduleData.WatchTask? {
        let now = Date()
        return activeTasks.first { $0.date >= now } ?? activeTasks.first
    }

    func requestUpdate() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "scheduleUpdate"], replyHandler: nil)
    }

    /// Send a new task to iPhone for creation.
    /// Send a quick check-in (mood + energy) to iPhone for processing.
    func sendCheckIn(_ message: [String: Any]) {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }

        // Optimistically update completed check-ins. Synthesize a base
        // schedule when scheduleData is nil (first-launch user with no sync
        // yet) so the user gets visible feedback that their tap landed —
        // previously this dropped silently.
        guard let slot = message["timeSlot"] as? String else { return }
        let base = scheduleData ?? WatchScheduleData(
            tasks: [], streakDays: 0, completedToday: 0, totalToday: 0,
            quoteText: nil, quoteAuthor: nil, nextCheckIn: nil, updatedAt: Date(),
            bodyScore: nil, mindScore: nil, heartScore: nil, spiritScore: nil,
            userName: nil, aiInsight: nil, completedCheckIns: nil
        )
        var completed = base.completedCheckIns ?? []
        if !completed.contains(slot) { completed.append(slot) }
        let updated = WatchScheduleData(
            tasks: base.tasks,
            streakDays: base.streakDays,
            completedToday: base.completedToday,
            totalToday: base.totalToday,
            quoteText: base.quoteText,
            quoteAuthor: base.quoteAuthor,
            nextCheckIn: nextCheckInAfter(slot),
            updatedAt: Date(),
            bodyScore: base.bodyScore,
            mindScore: base.mindScore,
            heartScore: base.heartScore,
            spiritScore: base.spiritScore,
            userName: base.userName,
            aiInsight: base.aiInsight,
            completedCheckIns: completed
        )
        persistAndUpdate(updated)
    }

    private func nextCheckInAfter(_ slot: String) -> String? {
        let order = ["Morning", "Midday", "Afternoon", "Night"]
        guard let idx = order.firstIndex(of: slot) else { return nil }
        let completed = scheduleData?.completedCheckIns ?? []
        for i in (idx + 1)..<order.count {
            if !completed.contains(order[i]) { return order[i] }
        }
        return nil // All done
    }

    /// Send a new task to iPhone for creation.
    func addTask(title: String, priority: String, date: Date, hasTime: Bool, dimensions: String? = nil) {
        var message: [String: Any] = [
            "addTask": true,
            "title": title,
            "priority": priority,
            "date": date.timeIntervalSince1970,
            "hasTime": hasTime
        ]
        if let dimensions { message["dimensions"] = dimensions }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }

        // Optimistically add to local schedule
        if var data = scheduleData {
            let newTask = WatchScheduleData.WatchTask(
                id: UUID().uuidString,
                title: title,
                date: date,
                priorityRaw: priority,
                categoryRaw: "Personal",
                done: false,
                isCalendarEvent: false,
                recurrenceRaw: nil,
                dimensionsRaw: dimensions
            )
            let updated = WatchScheduleData(
                tasks: (data.tasks + [newTask]).sorted { $0.date < $1.date },
                streakDays: data.streakDays,
                completedToday: data.completedToday,
                totalToday: data.totalToday + 1,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }
    }

    /// Delete a task from both Watch (optimistic) and iPhone.
    func deleteTask(_ taskID: String) {
        // Optimistically remove from local schedule
        if let data = scheduleData,
           let taskToDelete = data.tasks.first(where: { $0.id == taskID }) {
            let updated = WatchScheduleData(
                tasks: data.tasks.filter { $0.id != taskID },
                streakDays: data.streakDays,
                completedToday: taskToDelete.done ? max(0, data.completedToday - 1) : data.completedToday,
                totalToday: max(0, data.totalToday - 1),
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }

        // Send to iPhone
        let message: [String: Any] = ["deleteTask": taskID]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Send a task completion toggle to the iPhone for processing.
    func toggleTaskCompletion(_ taskID: String) {
        // Optimistically update local state — but ONLY if the task exists in
        // our local view of the schedule. Otherwise the completedToday delta
        // would be -1 for a phantom task (e.g. replayed userInfo for a task
        // already deleted on iPhone), drifting the counter below truth.
        if let data = scheduleData,
           let original = data.tasks.first(where: { $0.id == taskID }) {
            let willBeDone = !original.done
            let updatedTasks = data.tasks.map { task -> WatchScheduleData.WatchTask in
                guard task.id == taskID else { return task }
                return WatchScheduleData.WatchTask(
                    id: task.id,
                    title: task.title,
                    date: task.date,
                    priorityRaw: task.priorityRaw,
                    categoryRaw: task.categoryRaw,
                    done: willBeDone,
                    isCalendarEvent: task.isCalendarEvent,
                    recurrenceRaw: task.recurrenceRaw,
                    dimensionsRaw: task.dimensionsRaw
                )
            }
            let completedDelta = willBeDone ? 1 : -1
            let updated = WatchScheduleData(
                tasks: updatedTasks,
                streakDays: data.streakDays,
                completedToday: max(0, data.completedToday + completedDelta),
                totalToday: data.totalToday,
                quoteText: data.quoteText,
                quoteAuthor: data.quoteAuthor,
                nextCheckIn: data.nextCheckIn,
                updatedAt: Date(),
                bodyScore: data.bodyScore, mindScore: data.mindScore,
                heartScore: data.heartScore, spiritScore: data.spiritScore,
                userName: data.userName, aiInsight: data.aiInsight,
                completedCheckIns: data.completedCheckIns
            )
            persistAndUpdate(updated)
        }

        // Always forward to iPhone. Even when the local task is missing the
        // iPhone may still own the canonical record (eventual consistency).
        let message: [String: Any] = ["toggleTask": taskID]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil)
        } else {
            // Use transferUserInfo as fallback for when iPhone isn't reachable
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - Persistence

    private static let apiKeyAccount = "com.myaissistant.watch-api-key"

    private func extractAPIKey(from dict: [String: Any]) {
        guard let key = dict["apiKey"] as? String, !key.isEmpty else { return }
        // Shape-validate before committing to Keychain. Anthropic keys
        // start with "sk-ant-" and are long base64-ish. Rejecting
        // obvious non-keys prevents a garbled/injected payload from
        // silently overwriting the real key and breaking AI on Watch.
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-ant-"), trimmed.count >= 32 else { return }
        // No-op if the key hasn't changed — avoids excess Keychain churn
        // every applicationContext delivery.
        guard trimmed != apiKey else { return }
        self.apiKey = trimmed
        saveAPIKeyToKeychain(trimmed)
    }

    private func loadAPIKeyFromCache() {
        apiKey = loadAPIKeyFromKeychain()
    }

    private func saveAPIKeyToKeychain(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            // Migrate from old UserDefaults storage if present
            if let old = UserDefaults.standard.string(forKey: "watchAPIKey") {
                saveAPIKeyToKeychain(old)
                UserDefaults.standard.removeObject(forKey: "watchAPIKey")
                return old
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func persistAndUpdate(_ data: WatchScheduleData) {
        self.scheduleData = data
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let encoded = try? encoder.encode(data) {
            UserDefaults.standard.set(encoded, forKey: "watchScheduleCache")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Apply an iPhone-originated payload with a staleness guard: if the
    /// incoming `updatedAt` is older than what we already have locally,
    /// drop the update. Prevents an iPhone reply that's in-flight during
    /// the user's optimistic edits from overwriting newer local state
    /// with an older authoritative snapshot.
    private func applyIncoming(_ incoming: WatchScheduleData) {
        if let current = scheduleData, incoming.updatedAt < current.updatedAt {
            // Stale — probably an iPhone reply that crossed our optimistic
            // write. Keep local state; the next authoritative payload will
            // have a fresh timestamp and win cleanly.
            return
        }
        persistAndUpdate(incoming)
    }

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: "watchScheduleCache") else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        scheduleData = try? decoder.decode(WatchScheduleData.self, from: data)
    }

    // MARK: - WCSessionDelegate
    //
    // WCSession invokes these on a background queue, so they MUST be
    // nonisolated. We hop to the main actor to mutate observable state.

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.hasAttemptedSync = true
            self.extractAPIKey(from: context)
            if let data = WatchScheduleData.from(context: context) {
                self.applyIncoming(data)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.hasAttemptedSync = true
            self.extractAPIKey(from: applicationContext)
            if let data = WatchScheduleData.from(context: applicationContext) {
                self.applyIncoming(data)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.hasAttemptedSync = true
            self.extractAPIKey(from: message)
            if let data = WatchScheduleData.from(context: message) {
                self.persistAndUpdate(data)
            }
        }
    }
}

#endif
