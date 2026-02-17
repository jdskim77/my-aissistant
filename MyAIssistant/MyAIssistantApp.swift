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
    private var backgroundTaskManager: BackgroundTaskManager?

    init() {
        let schema = Schema([
            TaskItem.self,
            ChatMessage.self,
            CheckInRecord.self,
            DailySnapshot.self,
            UserProfile.self,
            UsageTracker.self,
            CalendarLink.self
        ])
        let config = ModelConfiguration("MyAIssistant", isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])

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

        // Seed sample data on first launch
        DataSeeder.seedIfEmpty(context: context)

        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.taskManager, taskManager)
                .environment(\.patternEngine, patternEngine)
                .environment(\.checkInManager, checkInManager)
                .environment(\.calendarSyncManager, calendarSyncManager)
                .environment(\.usageGateManager, usageGateManager)
                .environment(\.subscriptionTier, subscriptionManager.currentTier)
                .environment(\.keychainService, keychainService)
                .environmentObject(subscriptionManager)
                .task {
                    await subscriptionManager.updateTier()
                    await subscriptionManager.loadProducts()

                    // Register and schedule background tasks
                    backgroundTaskManager?.registerAll()
                    backgroundTaskManager?.scheduleDailySnapshot()
                    backgroundTaskManager?.scheduleWeeklyReview()
                    backgroundTaskManager?.scheduleCalendarSync()
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

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
        // Handle notification taps — deep linking will be added in later phases
        let userInfo = response.notification.request.content.userInfo
        _ = response.actionIdentifier
        _ = userInfo
    }
}
