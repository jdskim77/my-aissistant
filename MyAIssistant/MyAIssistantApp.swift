import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyAIssistantApp: App {
    let modelContainer: ModelContainer
    @State private var taskManager: TaskManager
    @State private var patternEngine: PatternEngine
    @State private var checkInManager: CheckInManager
    @State private var calendarSyncManager: CalendarSyncManager
    @State private var usageGateManager: UsageGateManager
    @StateObject private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: MyAIssistantMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Database corrupted — delete and recreate to prevent permanent launch crash
            let storeURL = config.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM sidecar files
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            container = (try? ModelContainer(
                for: schema,
                migrationPlan: MyAIssistantMigrationPlan.self,
                configurations: [config]
            )) ?? ModelContainer.fallbackInMemory(schema: schema)
        }

        self.modelContainer = container
        let context = container.mainContext
        let tm = TaskManager(modelContext: context)
        let pe = PatternEngine(modelContext: context, keychainService: keychainService)
        let csm = CalendarSyncManager(modelContext: context)

        self._taskManager = State(initialValue: tm)
        self._patternEngine = State(initialValue: pe)
        self._checkInManager = State(initialValue: CheckInManager(modelContext: context))
        self._calendarSyncManager = State(initialValue: csm)
        self._usageGateManager = State(initialValue: UsageGateManager(modelContext: context))

        // Background task manager
        self.backgroundTaskManager = BackgroundTaskManager(
            modelContext: context,
            patternEngine: pe,
            calendarSyncManager: csm
        )

        // Register background tasks (must happen during init, before app finishes launching)
        self.backgroundTaskManager?.registerAll()

        // Seed sample data on first launch
        DataSeeder.seedIfEmpty(context: context)

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(themeManager.themeID)
                .preferredColorScheme(themeManager.selectedTheme.isDark ? .dark : .light)
                .environment(\.taskManager, taskManager)
                .environment(\.patternEngine, patternEngine)
                .environment(\.checkInManager, checkInManager)
                .environment(\.calendarSyncManager, calendarSyncManager)
                .environment(\.usageGateManager, usageGateManager)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.keychainService, keychainService)
                .environment(\.greetingManager, greetingManager)
                .environmentObject(subscriptionManager)
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Schedule background tasks
                    backgroundTaskManager?.scheduleDailySnapshot()
                    backgroundTaskManager?.scheduleWeeklyReview()
                    backgroundTaskManager?.scheduleCalendarSync()
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Notification Delegate

extension Notification.Name {
    static let didTapNotification = Notification.Name("didTapNotification")
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Stores the destination when the app is launched from a notification tap (cold launch).
    /// ContentView reads and clears this on appear.
    var pendingDestination: String?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        // Determine which screen to open
        let destination: String
        switch category {
        case "CHECKIN":
            destination = "home"
        case "TASK":
            destination = "schedule"
        case "ALARM":
            // Snooze: reschedule 5 minutes from now, don't open app
            if action == "SNOOZE_ALARM", let alarmID = userInfo["alarmID"] as? String {
                let snoozeTime = Date().addingTimeInterval(5 * 60)
                guard let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent else {
                    return
                }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: snoozeTime)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "alarm-\(alarmID)-snooze", content: content, trigger: trigger)
                try? await center.add(request)
                return
            }
            destination = "home"
        default:
            destination = "home"
        }

        await MainActor.run {
            // Store for cold-launch case (ContentView not yet mounted)
            Self.shared.pendingDestination = destination

            NotificationCenter.default.post(
                name: .didTapNotification,
                object: nil,
                userInfo: ["destination": destination, "category": category, "originalUserInfo": userInfo]
            )
        }
    }
}

// MARK: - ModelContainer Recovery

extension ModelContainer {
    /// Last-resort in-memory container so the app can at least launch.
    static func fallbackInMemory(schema: Schema) -> ModelContainer {
        let inMemory = ModelConfiguration("MyAIssistant-fallback", isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [inMemory])
    }
}
