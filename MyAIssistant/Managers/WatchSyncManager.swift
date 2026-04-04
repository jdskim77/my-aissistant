import CryptoKit
import Foundation
import WatchConnectivity

// MARK: - WatchConnectivity Payload Encryption

/// Simple symmetric encryption for API keys sent over WatchConnectivity.
/// Derives a key from the app bundle ID so only this app can decrypt.
enum WatchPayloadCrypto {
    /// Derive a 256-bit symmetric key from the bundle identifier.
    private static var symmetricKey: SymmetricKey {
        let seed = (Bundle.main.bundleIdentifier ?? "com.myaissistant").data(using: .utf8)!
        let hash = SHA256.hash(data: seed)
        return SymmetricKey(data: hash)
    }

    /// Encrypt a string into a combined sealed-box Data (nonce + ciphertext + tag).
    static func encrypt(_ plaintext: String) -> Data? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        guard let sealedBox = try? ChaChaPoly.seal(data, using: symmetricKey) else { return nil }
        return sealedBox.combined
    }

    /// Decrypt combined sealed-box Data back into the original string.
    static func decrypt(_ combined: Data) -> String? {
        guard let sealedBox = try? ChaChaPoly.SealedBox(combined: combined) else { return nil }
        guard let data = try? ChaChaPoly.open(sealedBox, using: symmetricKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Manages iPhone → Watch data sync via WatchConnectivity.
/// Sends schedule snapshots to the Watch app whenever tasks change.
@MainActor
final class WatchSyncManager: NSObject, ObservableObject {
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
        guard let encryptedKey = WatchPayloadCrypto.encrypt(apiKey) else { return }
        let message: [String: Any] = ["apiKeyEncrypted": encryptedKey]
        // Use both channels to ensure delivery
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
        }
        // Also include in application context for when Watch isn't reachable
        var context = session.applicationContext
        context["apiKeyEncrypted"] = encryptedKey
        context["textSize"] = TextSizeManager.shared.selectedSize.rawValue
        try? session.updateApplicationContext(context)
    }

    /// Send current schedule to Watch. Call after any task mutation.
    func syncSchedule(
        tasks: [TaskItem],
        streak: Int,
        quoteText: String?,
        quoteAuthor: String?
    ) {
        guard let session else { return }

        // If session hasn't activated yet, queue this sync for later
        guard isActivated else {
            pendingSync = { [weak self] in
                self?.syncSchedule(tasks: tasks, streak: streak, quoteText: quoteText, quoteAuthor: quoteAuthor)
            }
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)

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
                recurrenceRaw: task.recurrenceRaw
            )
        }

        // Determine next check-in
        let hour = calendar.component(.hour, from: Date())
        let nextCheckIn: String? = {
            if hour < 8 { return "Morning" }
            if hour < 13 { return "Midday" }
            if hour < 18 { return "Afternoon" }
            if hour < 22 { return "Night" }
            return nil
        }()

        let data = WatchScheduleData(
            tasks: watchTasks,
            streakDays: streak,
            completedToday: todayTasks.filter(\.done).count,
            totalToday: todayTasks.count,
            quoteText: quoteText,
            quoteAuthor: quoteAuthor,
            nextCheckIn: nextCheckIn,
            updatedAt: Date()
        )

        var context = data.toDictionary()
        // Include encrypted API key in context so Watch always has it
        let keychain = KeychainService()
        if let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty,
           let encryptedKey = WatchPayloadCrypto.encrypt(apiKey) {
            context["apiKeyEncrypted"] = encryptedKey
        }
        // Include text size preference
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
    }
}

extension Notification.Name {
    static let watchRequestedUpdate = Notification.Name("watchRequestedUpdate")
    static let watchToggledTask = Notification.Name("watchToggledTask")
    static let watchAddedTask = Notification.Name("watchAddedTask")
    static let taskCompletionChanged = Notification.Name("taskCompletionChanged")
}
