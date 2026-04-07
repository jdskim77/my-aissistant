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
    @State private var wisdomManager: WisdomManager
    @State private var insightEngine: InsightEngine
    @State private var chatManager: ChatManager
    @State private var balanceManager: BalanceManager
    @State private var habitManager: HabitManager
    @State private var checkInBehaviorEngine: CheckInBehaviorEngine
    @State private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    @State private var notificationManager = NotificationManager()
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        let schema = Schema(AppSchema.allModels)
        let container: ModelContainer

        // Attempt 1: CloudKit-synced store
        if let cloud = Self.createCloudContainer(schema: schema) {
            container = cloud
        }
        // Attempt 2: Local-only single store (no CloudKit)
        else if let local = Self.createLocalOnlyContainer(schema: schema) {
            container = local
        }
        // Attempt 3: In-memory fallback (data won't persist)
        else {
            container = ModelContainer.fallbackInMemory(schema: schema)
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
        self._wisdomManager = State(initialValue: WisdomManager(modelContext: context))
        self._insightEngine = State(initialValue: InsightEngine(modelContext: context))

        let bm = BalanceManager(modelContext: context)

        let cm = ChatManager(modelContext: context)
        cm.taskManager = tm
        cm.patternEngine = pe
        cm.balanceManager = bm
        cm.keychainService = keychainService
        cm.calendarSyncManager = csm
        self._chatManager = State(initialValue: cm)
        self._balanceManager = State(initialValue: bm)
        self._habitManager = State(initialValue: HabitManager(modelContext: context))
        self._checkInBehaviorEngine = State(initialValue: CheckInBehaviorEngine(modelContext: context))

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
                .environment(\.wisdomManager, wisdomManager)
                .environment(\.insightEngine, insightEngine)
                .environment(\.chatManager, chatManager)
                .environment(\.balanceManager, balanceManager)
                .environment(\.habitManager, habitManager)
                .environment(\.checkInBehaviorEngine, checkInBehaviorEngine)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.keychainService, keychainService)
                .environment(\.greetingManager, greetingManager)
                .environment(\.notificationManager, notificationManager)
                .environment(\.subscriptionManager, subscriptionManager)
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Schedule adaptive check-in reminders based on streak
                    let streak = patternEngine.currentStreak()
                    notificationManager.scheduleAdaptiveCheckInReminders(currentStreak: streak)

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
        case "CHECKIN", "STREAK_REMINDER":
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

// MARK: - ModelContainer Factory Methods

extension MyAIssistantApp {
    private static let appGroupID = "group.com.myaissistant.shared"
    private static let storeFilename = "MyAIssistant.store"

    /// Resolves the SwiftData store URL inside the App Group's Application Support
    /// directory, creating intermediate directories first. Returns nil if the
    /// App Group container is unavailable (e.g. entitlements mismatch).
    private static func appGroupStoreURL() -> URL? {
        let fm = FileManager.default
        guard let containerURL = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let appSupport = containerURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        do {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return appSupport.appendingPathComponent(storeFilename)
    }

    static func createCloudContainer(schema: Schema) -> ModelContainer? {
        let config: ModelConfiguration
        if let url = appGroupStoreURL() {
            config = ModelConfiguration("MyAIssistant", schema: schema, url: url, cloudKitDatabase: .automatic)
        } else {
            config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        }
        return try? ModelContainer(for: schema, configurations: [config])
    }

    static func createLocalOnlyContainer(schema: Schema) -> ModelContainer? {
        let config: ModelConfiguration
        if let url = appGroupStoreURL() {
            config = ModelConfiguration("MyAIssistant", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }
        return try? ModelContainer(for: schema, configurations: [config])
    }
}

extension ModelContainer {
    /// Last-resort in-memory container so the app can at least launch.
    static func fallbackInMemory(schema: Schema) -> ModelContainer {
        let inMemory = ModelConfiguration("MyAIssistant-fallback", isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("Cannot create even an in-memory ModelContainer: \(error)")
        }
    }
}
