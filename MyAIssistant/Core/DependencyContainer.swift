import SwiftUI
import SwiftData

// MARK: - TaskManager Environment Key

struct TaskManagerKey: EnvironmentKey {
    static let defaultValue: TaskManager? = nil
}

extension EnvironmentValues {
    var taskManager: TaskManager? {
        get { self[TaskManagerKey.self] }
        set { self[TaskManagerKey.self] = newValue }
    }
}

// MARK: - PatternEngine Environment Key

struct PatternEngineKey: EnvironmentKey {
    static let defaultValue: PatternEngine? = nil
}

extension EnvironmentValues {
    var patternEngine: PatternEngine? {
        get { self[PatternEngineKey.self] }
        set { self[PatternEngineKey.self] = newValue }
    }
}

// MARK: - KeychainService Environment Key

struct KeychainServiceKey: EnvironmentKey {
    static let defaultValue: KeychainService = KeychainService()
}

extension EnvironmentValues {
    var keychainService: KeychainService {
        get { self[KeychainServiceKey.self] }
        set { self[KeychainServiceKey.self] = newValue }
    }
}

// MARK: - SubscriptionTier Environment Key

struct SubscriptionTierKey: EnvironmentKey {
    static let defaultValue: SubscriptionTier = .free
}

extension EnvironmentValues {
    var subscriptionTier: SubscriptionTier {
        get { self[SubscriptionTierKey.self] }
        set { self[SubscriptionTierKey.self] = newValue }
    }
}

// MARK: - CheckInManager Environment Key

struct CheckInManagerKey: EnvironmentKey {
    static let defaultValue: CheckInManager? = nil
}

extension EnvironmentValues {
    var checkInManager: CheckInManager? {
        get { self[CheckInManagerKey.self] }
        set { self[CheckInManagerKey.self] = newValue }
    }
}

// MARK: - CalendarSyncManager Environment Key

struct CalendarSyncManagerKey: EnvironmentKey {
    static let defaultValue: CalendarSyncManager? = nil
}

extension EnvironmentValues {
    var calendarSyncManager: CalendarSyncManager? {
        get { self[CalendarSyncManagerKey.self] }
        set { self[CalendarSyncManagerKey.self] = newValue }
    }
}

// MARK: - GreetingManager Environment Key

struct GreetingManagerKey: EnvironmentKey {
    static let defaultValue: GreetingManager? = nil
}

extension EnvironmentValues {
    var greetingManager: GreetingManager? {
        get { self[GreetingManagerKey.self] }
        set { self[GreetingManagerKey.self] = newValue }
    }
}

// MARK: - WisdomManager Environment Key

struct WisdomManagerKey: EnvironmentKey {
    static let defaultValue: WisdomManager? = nil
}

extension EnvironmentValues {
    var wisdomManager: WisdomManager? {
        get { self[WisdomManagerKey.self] }
        set { self[WisdomManagerKey.self] = newValue }
    }
}

// MARK: - UsageGateManager Environment Key

struct UsageGateManagerKey: EnvironmentKey {
    static let defaultValue: UsageGateManager? = nil
}

extension EnvironmentValues {
    var usageGateManager: UsageGateManager? {
        get { self[UsageGateManagerKey.self] }
        set { self[UsageGateManagerKey.self] = newValue }
    }
}

// MARK: - NotificationManager Environment Key

struct NotificationManagerKey: EnvironmentKey {
    static let defaultValue: NotificationManager? = nil
}

extension EnvironmentValues {
    var notificationManager: NotificationManager? {
        get { self[NotificationManagerKey.self] }
        set { self[NotificationManagerKey.self] = newValue }
    }
}

// MARK: - BalanceManager Environment Key

struct BalanceManagerKey: EnvironmentKey {
    static let defaultValue: BalanceManager? = nil
}

extension EnvironmentValues {
    var balanceManager: BalanceManager? {
        get { self[BalanceManagerKey.self] }
        set { self[BalanceManagerKey.self] = newValue }
    }
}

// MARK: - ChatManager Environment Key

struct ChatManagerKey: EnvironmentKey {
    static let defaultValue: ChatManager? = nil
}

extension EnvironmentValues {
    var chatManager: ChatManager? {
        get { self[ChatManagerKey.self] }
        set { self[ChatManagerKey.self] = newValue }
    }
}

// MARK: - HabitManager Environment Key

struct HabitManagerKey: EnvironmentKey {
    static let defaultValue: HabitManager? = nil
}

extension EnvironmentValues {
    var habitManager: HabitManager? {
        get { self[HabitManagerKey.self] }
        set { self[HabitManagerKey.self] = newValue }
    }
}

// MARK: - CheckInBehaviorEngine Environment Key

struct CheckInBehaviorEngineKey: EnvironmentKey {
    static let defaultValue: CheckInBehaviorEngine? = nil
}

extension EnvironmentValues {
    var checkInBehaviorEngine: CheckInBehaviorEngine? {
        get { self[CheckInBehaviorEngineKey.self] }
        set { self[CheckInBehaviorEngineKey.self] = newValue }
    }
}

// MARK: - SubscriptionManager Environment Key

struct SubscriptionManagerKey: EnvironmentKey {
    @MainActor static let defaultValue: SubscriptionManager = SubscriptionManager()
}

extension EnvironmentValues {
    var subscriptionManager: SubscriptionManager {
        get { self[SubscriptionManagerKey.self] }
        set { self[SubscriptionManagerKey.self] = newValue }
    }
}

// MARK: - InsightEngine Environment Key

struct InsightEngineKey: EnvironmentKey {
    static let defaultValue: InsightEngine? = nil
}

extension EnvironmentValues {
    var insightEngine: InsightEngine? {
        get { self[InsightEngineKey.self] }
        set { self[InsightEngineKey.self] = newValue }
    }
}
