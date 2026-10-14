import Foundation
import SwiftData
import UserNotifications

/// Executes the Feature 1 "10-second quick mood check-in" when the user
/// taps a mood action on a CHECKIN or STREAK_REMINDER notification.
///
/// This runs from `NotificationDelegate.userNotificationCenter(_:didReceive:)`,
/// which can fire while the app is NOT running (cold background launch —
/// none of the mood actions carry `.foreground`, so iOS invokes the app's
/// UNUserNotificationCenterDelegate without creating a UI scene). That means
/// this code cannot rely on `MyAIssistantApp`'s `@State` managers/environment
/// — they only exist once a scene has launched. Instead it opens its own
/// ModelContainer pointed at the same App Group store, exactly like
/// `IntentModelContainer` does for App Intents extensions.
@MainActor
enum QuickCheckInHandler {

    /// Same App Group SQLite file every surface (app / widgets / intents /
    /// this handler) shares — see `IntentModelContainer` and
    /// `MyAIssistantApp.appGroupStoreURL()` for the sibling implementations.
    private static func appGroupStoreURL() -> URL? {
        let fm = FileManager.default
        guard let containerURL = fm.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupID
        ) else { return nil }
        let appSupport = containerURL.appendingPathComponent(
            "Library/Application Support", isDirectory: true
        )
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("MyAIssistant.store")
    }

    /// Lazily-created container reused for the lifetime of this background
    /// delegate call (and any subsequent ones in the same process). Built
    /// from `AppSchema.allModels` — every model the quick check-in path
    /// touches (CheckInRecord, CheckInBehavior, CheckInPreference via
    /// CheckInBehaviorEngine, TaskItem/HabitItem via PatternEngine's streak
    /// walk) is already in that single shared schema, so no partial-schema
    /// container is needed here.
    private static var sharedContainer: ModelContainer?

    private static func resolveContainer() -> ModelContainer? {
        if let sharedContainer { return sharedContainer }
        let schema = Schema(AppSchema.allModels)
        guard let url = appGroupStoreURL() else { return nil }
        let config = ModelConfiguration(
            "MyAIssistant", schema: schema, url: url, cloudKitDatabase: .automatic
        )
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            sharedContainer = container
            return container
        }
        // Local fallback mirrors IntentModelContainer's degraded path.
        let localConfig = ModelConfiguration(
            "MyAIssistant", schema: schema, url: url, cloudKitDatabase: .none
        )
        let container = try? ModelContainer(for: schema, configurations: [localConfig])
        sharedContainer = container
        return container
    }

    /// Entry point called from the notification delegate. `actionIdentifier`
    /// is expected to be one of `QuickCheckInLogic.moodActionIdentifiers`;
    /// callers should check that before invoking this (kept as a guard here
    /// too, so misrouted calls are a silent no-op rather than a crash).
    static func handle(
        actionIdentifier: String,
        explicitSlotRaw: String?,
        completion: @escaping () -> Void
    ) {
        guard let moodValue = QuickCheckInLogic.moodValue(forActionIdentifier: actionIdentifier) else {
            completion()
            return
        }
        guard let container = resolveContainer() else {
            completion()
            return
        }

        let context = container.mainContext
        let slot = QuickCheckInLogic.deriveTimeSlot(
            explicitRaw: explicitSlotRaw,
            hour: Calendar.current.component(.hour, from: Date())
        )
        guard let timeSlot = CheckInTime(rawValue: slot.rawValue) else {
            completion()
            return
        }

        let checkInManager = CheckInManager(modelContext: context)
        let existingToday = checkInManager.todayCheckIns().map {
            QuickCheckInLogic.ExistingRecordSummary(timeSlotRaw: $0.timeSlotRaw, completed: $0.completed)
        }
        let decision = QuickCheckInLogic.decide(for: slot, existingToday: existingToday)

        guard decision != .alreadyCompleted else {
            completion()
            return
        }

        let record: CheckInRecord
        switch decision {
        case .completeExistingPending:
            let descriptor = FetchDescriptor<CheckInRecord>()
            let todayRecords = (try? context.fetch(descriptor)) ?? []
            let startOfDay = Calendar.current.startOfDay(for: Date())
            guard let found = todayRecords.first(where: {
                $0.timeSlotRaw == slot.rawValue && !$0.completed && $0.date >= startOfDay
            }) else {
                // Shouldn't happen given `decide`'s contract, but fail safe
                // rather than double-creating a record for this slot.
                completion()
                return
            }
            record = found
        case .createAndComplete:
            record = checkInManager.startCheckIn(timeSlot: timeSlot)
        case .alreadyCompleted:
            completion()
            return
        }

        checkInManager.completeCheckIn(
            record,
            mood: moodValue,
            energyLevel: nil,
            notes: nil,
            aiSummary: nil,
            isQuickCheckIn: true
        )

        // Mirror CheckInDetailView.finalizeCheckIn()'s side effects exactly.
        let checkInBehaviorEngine = CheckInBehaviorEngine(modelContext: context)
        checkInBehaviorEngine.recordCompletion(window: timeSlot)
        checkInBehaviorEngine.syncWidgetData()

        let patternEngine = PatternEngine(modelContext: context)
        let streak = patternEngine.currentStreak()

        let notificationManager = NotificationManager()
        notificationManager.cancelStreakReminder()
        notificationManager.scheduleAdaptiveCheckInReminders(currentStreak: streak, alreadyCheckedInToday: true)

        let insightEngine = InsightEngine(modelContext: context)
        let insightText = insightEngine.todayInsight()?.text

        postRewardNotification(moodValue: moodValue, streak: streak, insightText: insightText)

        completion()
    }

    private static func postRewardNotification(moodValue: Int, streak: Int, insightText: String?) {
        let content = UNMutableNotificationContent()
        content.title = QuickCheckInLogic.rewardNotificationTitle(moodValue: moodValue)
        content.body = QuickCheckInLogic.rewardNotificationBody(
            moodValue: moodValue, streak: streak, insightText: insightText
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "quick-checkin-reward-\(UUID().uuidString)",
            content: content,
            trigger: nil // fire immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
