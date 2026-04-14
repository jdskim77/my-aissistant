import SwiftUI
import SwiftData
import UserNotifications
import os.log

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
    @State private var networkMonitor = NetworkMonitor()
    @State private var dailyRecapGenerator: DailyRecapGenerator?
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        // Initialize crash reporting FIRST so we capture any startup crashes.
        // No-op until SentryConfig.dsn is set.
        SentryConfig.start()
        DiagnosticsManager.shared.startCollecting()
        AppLogger.app.notice("App launching — \(Bundle.main.appVersion, privacy: .public)+\(Bundle.main.buildNumber, privacy: .public)")

        // One-time migration: force voice mode OFF for existing testers who had it
        // auto-enabled before the default was changed. Prevents unexpected mic
        // auto-restart after AI replies. Runs once per install.
        let voiceMigrationKey = "didMigrateVoiceModeDefault_v1"
        if !UserDefaults.standard.bool(forKey: voiceMigrationKey) {
            UserDefaults.standard.set(false, forKey: AppConstants.voiceModeDefaultKey)
            UserDefaults.standard.set(true, forKey: voiceMigrationKey)
        }

        // Use the versioned schema baseline. SchemaV1 is the v1.0 ship state;
        // any future model change must add SchemaV2 + a MigrationStage in
        // AppMigrationPlan.
        let schema = Schema(versionedSchema: SchemaV1.self)
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
        let ugm = UsageGateManager(modelContext: context)
        let bm = BalanceManager(modelContext: context)

        tm.calendarSyncManager = csm
        tm.balanceManager = bm
        self._taskManager = State(initialValue: tm)
        self._patternEngine = State(initialValue: pe)
        self._checkInManager = State(initialValue: CheckInManager(modelContext: context))
        self._calendarSyncManager = State(initialValue: csm)
        self._usageGateManager = State(initialValue: ugm)
        self._wisdomManager = State(initialValue: WisdomManager(modelContext: context))
        self._insightEngine = State(initialValue: InsightEngine(modelContext: context))

        let cm = ChatManager(modelContext: context)
        cm.taskManager = tm
        cm.patternEngine = pe
        cm.balanceManager = bm
        cm.keychainService = keychainService
        cm.calendarSyncManager = csm
        cm.usageGateManager = ugm
        self._chatManager = State(initialValue: cm)
        self._balanceManager = State(initialValue: bm)
        let hm = HabitManager(modelContext: context)
        self._habitManager = State(initialValue: hm)
        let cibe = CheckInBehaviorEngine(modelContext: context)
        self._checkInBehaviorEngine = State(initialValue: cibe)

        // Background task manager — pass the behavior engine so daily snapshots
        // can recalculate behavioral stats and use the active window count.
        // Daily Recap generator — assembles context and calls AI for post-check-in insights
        let drg = DailyRecapGenerator(modelContext: context, keychainService: keychainService)
        drg.patternEngine = pe
        drg.balanceManager = bm
        drg.taskManager = tm
        drg.chatManager = cm
        drg.habitManager = hm
        self._dailyRecapGenerator = State(initialValue: drg)

        self.backgroundTaskManager = BackgroundTaskManager(
            modelContext: context,
            patternEngine: pe,
            calendarSyncManager: csm,
            checkInBehaviorEngine: cibe
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
                .environment(\.networkMonitor, networkMonitor)
                .environment(\.dailyRecapGenerator, dailyRecapGenerator)
                .environment(\.userName, UserDefaults.standard.string(forKey: "user_name"))
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Adaptive check-in engine: seed default preferences on first launch,
                    // then recalculate behavioral stats (14-day rolling window). Idempotent.
                    checkInBehaviorEngine.seedDefaultPreferencesIfNeeded()
                    checkInBehaviorEngine.recalculateIfNeeded()

                    // Schedule adaptive check-in reminders based on streak
                    let streak = patternEngine.currentStreak()
                    notificationManager.scheduleAdaptiveCheckInReminders(currentStreak: streak)

                    // Wire notification manager into habit manager for auto-rescheduling
                    habitManager.notificationManager = notificationManager
                    habitManager.rescheduleHabitReminders()

                    // Intelligent habit reminder coordination
                    let coordinator = HabitReminderCoordinator(modelContext: modelContainer.mainContext)
                    coordinator.patternEngine = patternEngine
                    coordinator.taskManager = taskManager
                    coordinator.notificationManager = notificationManager
                    coordinator.coordinateToday()

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
                    let hasTime = info["hasTime"] as? Bool ?? false
                    let priority = TaskPriority(rawValue: priorityRaw) ?? .medium

                    // If no time was specified, use start-of-day so it sorts
                    // correctly and doesn't show a spurious "12:00 AM" time.
                    let finalDate = hasTime ? date : Calendar.current.startOfDay(for: date)
                    let task = TaskItem(
                        title: title,
                        category: .personal,
                        priority: priority,
                        date: finalDate,
                        icon: "📝"
                    )
                    // Apply dimensions from Watch (comma-separated raw values)
                    if let dimString = info["dimensions"] as? String {
                        task.dimensions = dimString.split(separator: ",")
                            .compactMap { LifeDimension(rawValue: String($0)) }
                    }
                    taskManager.addTask(task)
                    taskManager.updateWidgetData()
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchDeletedTask)) { notification in
                    guard let taskID = notification.userInfo?["taskID"] as? String else { return }
                    if let task = taskManager.findTask(byID: taskID) {
                        taskManager.deleteTask(task)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchQuickCheckIn)) { notification in
                    guard let info = notification.userInfo,
                          let mood = info["mood"] as? Int,
                          let energy = info["energy"] as? Int,
                          let slotRaw = info["timeSlot"] as? String,
                          let slot = CheckInTime(rawValue: slotRaw) else { return }

                    // Deduplicate: check if this slot already has a completed check-in today
                    let existingToday = checkInManager.todayCheckIns().first {
                        $0.timeSlotRaw == slotRaw && $0.completed
                    }
                    guard existingToday == nil else { return }

                    let record = checkInManager.startCheckIn(timeSlot: slot)
                    checkInManager.completeCheckIn(record, mood: mood, energyLevel: energy, notes: nil, aiSummary: nil)
                    taskManager.updateWidgetData()
                }
                .onReceive(NotificationCenter.default.publisher(for: .habitCompletedFromNotification)) { notification in
                    guard let habitID = notification.userInfo?["habitID"] as? String else { return }
                    let descriptor = FetchDescriptor<HabitItem>(
                        predicate: #Predicate { $0.id == habitID }
                    )
                    if let habit = try? modelContainer.mainContext.fetch(descriptor).first {
                        habitManager.toggleCompletion(habit, for: Date())
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Notification Delegate

extension Notification.Name {
    static let didTapNotification = Notification.Name("didTapNotification")
    static let habitCompletedFromNotification = Notification.Name("habitCompletedFromNotification")
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Stores the destination when the app is launched from a notification tap (cold launch).
    /// ContentView reads and clears this on appear.
    var pendingDestination: String?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
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
        case "HABIT":
            // "Done" action: toggle habit completion via notification
            if action == "COMPLETE_HABIT", let habitID = userInfo["habitID"] as? String {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .habitCompletedFromNotification,
                        object: nil,
                        userInfo: ["habitID": habitID]
                    )
                }
            }
            destination = "home"
        case "ALARM":
            // Snooze: reschedule 5 minutes from now, don't open app
            if action == "SNOOZE_ALARM", let alarmID = userInfo["alarmID"] as? String {
                let snoozeTime = Date().addingTimeInterval(5 * 60)
                guard let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent else {
                    completionHandler()
                    return
                }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: snoozeTime)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: "alarm-\(alarmID)-snooze", content: content, trigger: trigger)
                center.add(request) { _ in completionHandler() }
                return
            }
            destination = "home"
        default:
            destination = "home"
        }

        // Store for cold-launch case (ContentView not yet mounted)
        Self.shared.pendingDestination = destination

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .didTapNotification,
                object: nil,
                userInfo: ["destination": destination, "category": category, "originalUserInfo": userInfo]
            )
        }

        completionHandler()
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
        return try? ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }

    static func createLocalOnlyContainer(schema: Schema) -> ModelContainer? {
        let config: ModelConfiguration
        if let url = appGroupStoreURL() {
            config = ModelConfiguration("MyAIssistant", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        }
        return try? ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
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
