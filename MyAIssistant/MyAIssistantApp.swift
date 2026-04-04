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
    @State private var balanceManager: BalanceManager
    @State private var chatManager: ChatManager
    @State private var habitManager: HabitManager
    @State private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [config]
            )
        } catch {
            // Database corrupted — back up then delete to prevent permanent launch crash
            let storeURL = config.url
            // Back up the corrupt database before deleting
            let backupURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("MyAIssistant_backup_\(Int(Date().timeIntervalSince1970)).sqlite")
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
            // Flag so the app can show a one-time recovery alert
            UserDefaults.standard.set(true, forKey: "databaseRecoveryOccurred")
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove WAL/SHM sidecar files
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            container = (try? ModelContainer(
                for: schema,
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
        self._balanceManager = State(initialValue: BalanceManager(modelContext: context))
        self._habitManager = State(initialValue: HabitManager(modelContext: context))

        let cm = ChatManager(modelContext: context)
        cm.taskManager = tm
        cm.patternEngine = pe
        cm.keychainService = keychainService
        cm.calendarSyncManager = csm
        self._chatManager = State(initialValue: cm)

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
                .withErrorBoundary()
                .id(themeManager.themeID)
                .preferredColorScheme(themeManager.selectedTheme.isDark ? .dark : .light)
                .environment(\.taskManager, taskManager)
                .environment(\.patternEngine, patternEngine)
                .environment(\.checkInManager, checkInManager)
                .environment(\.calendarSyncManager, calendarSyncManager)
                .environment(\.usageGateManager, usageGateManager)
                .environment(\.balanceManager, balanceManager)
                .environment(\.chatManager, chatManager)
                .environment(\.habitManager, habitManager)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.subscriptionManager, subscriptionManager)
                .environment(\.keychainService, keychainService)
                .environment(\.greetingManager, greetingManager)
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Schedule background tasks
                    backgroundTaskManager?.scheduleDailySnapshot()
                    backgroundTaskManager?.scheduleWeeklyReview()
                    backgroundTaskManager?.scheduleCalendarSync()

                    // Initialize WatchSyncManager early so WCSession can activate
                    _ = WatchSyncManager.shared
                    // Short delay to let WCSession finish activating before sending data
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    // Sync schedule + API key to Watch
                    WatchSyncManager.shared.syncAPIKey()
                    taskManager.updateWidgetData()
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchToggledTask)) { notification in
                    guard let taskID = notification.userInfo?["taskID"] as? String else { return }
                    if let task = taskManager.findTask(byID: taskID) {
                        taskManager.toggleCompletion(task)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchRequestedUpdate)) { _ in
                    taskManager.updateWidgetData()
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchAddedTask)) { notification in
                    guard let info = notification.userInfo,
                          let title = info["title"] as? String,
                          let priorityRaw = info["priority"] as? String,
                          let dateInterval = info["date"] as? TimeInterval else { return }

                    let date = Date(timeIntervalSince1970: dateInterval)
                    let priority = TaskPriority(rawValue: priorityRaw) ?? .medium
                    let task = TaskItem(
                        title: title,
                        category: .personal,
                        priority: priority,
                        date: date,
                        icon: "📝"
                    )
                    taskManager.addTask(task)
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
        // This is the absolute last resort — if even in-memory fails, the app cannot function
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("Cannot create even an in-memory ModelContainer: \(error)")
        }
    }
}
