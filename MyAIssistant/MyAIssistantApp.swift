import SwiftUI
import SwiftData
import UserNotifications

@main
struct MyAIssistantApp: App {
    /// Set to true if the database was corrupted and had to be reset on launch.
    static var databaseWasReset = false
    @State private var showDatabaseResetAlert = false

    let modelContainer: ModelContainer
    @State private var taskManager: TaskManager
    @State private var patternEngine: PatternEngine
    @State private var checkInManager: CheckInManager
    @State private var calendarSyncManager: CalendarSyncManager
    @State private var usageGateManager: UsageGateManager
    @State private var balanceManager: BalanceManager
    @StateObject private var subscriptionManager = SubscriptionManager()
    private let keychainService = KeychainService()
    @State private var greetingManager = GreetingManager()
    @State private var themeManager = ThemeManager.shared
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        // All model types — flat list for CloudKit compatibility (no versioned schema)
        let modelTypes: [any PersistentModel.Type] = [
            TaskItem.self,
            ChatMessage.self,
            CheckInRecord.self,
            DailySnapshot.self,
            UserProfile.self,
            UsageTracker.self,
            CalendarLink.self,
            ActivityEntry.self,
            AlarmEntry.self,
            FocusSession.self,
            HabitItem.self,
            DailyBalanceCheckIn.self,
            SeasonGoal.self,
            UserDimensionPreference.self,
            ActivityPattern.self
        ]
        let schema = Schema(modelTypes)

        // Local storage for now — CloudKit sync can be enabled once iCloud capability is configured
        let config = ModelConfiguration(
            "MyAIssistant",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Database corrupted — log and try without CloudKit
            AppLogger.data.critical("Database init failed: \(error.localizedDescription)")

            // Fallback: try local-only (no CloudKit)
            let localConfig = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
            do {
                container = try ModelContainer(for: schema, configurations: [localConfig])
                AppLogger.data.warning("Falling back to local-only storage (no iCloud sync)")
            } catch {
                // Last resort: delete and recreate
                AppLogger.data.critical("Database corrupted, resetting: \(error.localizedDescription)")
                Self.databaseWasReset = true

                let storeURL = localConfig.url
                try? FileManager.default.removeItem(at: storeURL)
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
                try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
                container = (try? ModelContainer(for: schema, configurations: [localConfig]))
                    ?? ModelContainer.fallbackInMemory(schema: schema)
            }
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

                    // Re-schedule check-in reminders on every launch (in case system cleared them)
                    let notificationManager = NotificationManager()
                    await notificationManager.checkAuthorizationStatus()
                    if notificationManager.isAuthorized {
                        notificationManager.scheduleCheckInReminders()
                    }

                    // Start listening for real-time calendar/reminder changes
                    calendarSyncManager.startListeningForChanges()

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
                .onReceive(NotificationCenter.default.publisher(for: .taskCompletionChanged)) { notification in
                    guard let info = notification.userInfo,
                          let extID = info["externalID"] as? String,
                          extID.hasPrefix("reminder:") else { return }
                    let done = info["done"] as? Bool ?? false
                    let reminderID = String(extID.dropFirst("reminder:".count))
                    Task {
                        if done {
                            try? await calendarSyncManager.eventKitService.completeReminder(identifier: reminderID)
                        } else {
                            try? await calendarSyncManager.eventKitService.uncompleteReminder(identifier: reminderID)
                        }
                    }
                }
                .alert("Data Reset", isPresented: $showDatabaseResetAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("The app's data was corrupted and had to be reset. Your tasks and check-ins have been cleared. We're sorry for the inconvenience.")
                }
                .onAppear {
                    if Self.databaseWasReset {
                        showDatabaseResetAlert = true
                        Self.databaseWasReset = false
                    }
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
        let inMemory = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            // Even in-memory failed — try with no named config
            print("🔴 fallbackInMemory failed: \(error)")
            return try! ModelContainer(
                for: UserProfile.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }
}
