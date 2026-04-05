import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyAIssistantApp: App {
    let modelContainer: ModelContainer
    @State private var showDatabaseRecoveryAlert = false
    @State private var taskManager: TaskManager
    @State private var patternEngine: PatternEngine
    @State private var checkInManager: CheckInManager
    @State private var calendarSyncManager: CalendarSyncManager
    @State private var usageGateManager: UsageGateManager
    @State private var balanceManager: BalanceManager
    @State private var chatManager: ChatManager
    @State private var habitManager: HabitManager
    @State private var checkInBehaviorEngine: CheckInBehaviorEngine
    @State private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        let container: ModelContainer

        // Attempt 1: CloudKit-synced store
        if let cloud = Self.createCloudContainer() {
            container = cloud
        }
        // Attempt 2: Local-only single store (no CloudKit — graceful degradation)
        else if let local = Self.createLocalOnlyContainer() {
            #if DEBUG
            print("[DB Recovery] CloudKit container failed, using local-only storage")
            #endif
            UserDefaults.standard.set(true, forKey: "databaseRecoveryOccurred")
            container = local
        }
        // Attempt 3: In-memory fallback (data won't persist)
        else {
            #if DEBUG
            print("[DB Recovery] All persistent containers failed, using in-memory")
            #endif
            UserDefaults.standard.set(true, forKey: "databaseRecoveryOccurred")
            container = Self.createInMemoryContainer()
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

        let cbe = CheckInBehaviorEngine(modelContext: context)
        self._checkInBehaviorEngine = State(initialValue: cbe)

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
            calendarSyncManager: csm,
            checkInBehaviorEngine: cbe
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
                .environment(\.checkInBehaviorEngine, checkInBehaviorEngine)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.subscriptionManager, subscriptionManager)
                .environment(\.keychainService, keychainService)
                .environment(\.greetingManager, greetingManager)
                .alert("Data Reset", isPresented: $showDatabaseRecoveryAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("The app's database was reset due to an update. Your previous data has been backed up but a fresh start was needed. We apologize for the inconvenience.")
                }
                .onAppear {
                    if UserDefaults.standard.bool(forKey: "databaseRecoveryOccurred") {
                        showDatabaseRecoveryAlert = true
                        UserDefaults.standard.set(false, forKey: "databaseRecoveryOccurred")
                    }
                }
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Seed default check-in preferences and recalculate behavior
                    checkInBehaviorEngine.seedDefaultPreferencesIfNeeded()
                    checkInBehaviorEngine.recalculateIfNeeded()

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

// MARK: - ModelContainer Factory Methods

extension MyAIssistantApp {
    /// Single store with CloudKit sync for all models
    static func createCloudContainer() -> ModelContainer? {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration(
            "MyAIssistant",
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        return try? ModelContainer(for: schema, configurations: [config])
    }

    /// Single local-only store for all models (no CloudKit, no split)
    static func createLocalOnlyContainer() -> ModelContainer? {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [config])
    }

    /// In-memory fallback — data won't persist but the app can launch
    static func createInMemoryContainer() -> ModelContainer {
        let schema = Schema(AppSchema.allModels)
        let config = ModelConfiguration("MyAIssistant-fallback", isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Cannot create even an in-memory ModelContainer: \(error)")
        }
    }
}

// MARK: - ModelContainer Fallback (used by IntentModelContainer)

extension ModelContainer {
    static func fallbackInMemory(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration("MyAIssistant-fallback", isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Cannot create even an in-memory ModelContainer: \(error)")
        }
    }
}
