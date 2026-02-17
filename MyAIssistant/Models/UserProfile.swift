import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: String
    var displayName: String
    var onboardingCompleted: Bool
    var notificationsEnabled: Bool
    var calendarSyncEnabled: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        displayName: String = "",
        onboardingCompleted: Bool = false,
        notificationsEnabled: Bool = false,
        calendarSyncEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.onboardingCompleted = onboardingCompleted
        self.notificationsEnabled = notificationsEnabled
        self.calendarSyncEnabled = calendarSyncEnabled
        self.createdAt = createdAt
    }
}
