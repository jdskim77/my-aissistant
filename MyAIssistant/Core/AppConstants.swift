import Foundation

enum AppConstants {
    // MARK: - API Endpoints
    static let anthropicEndpoint = "https://api.anthropic.com/v1/messages"
    static let anthropicAPIVersion = "2023-06-01"

    // MARK: - AI Models
    static let haikuModel = "claude-3-5-haiku-20241022"
    static let sonnetModel = "claude-sonnet-4-20250514"
    static let defaultMaxTokens = 1000

    // MARK: - Free Tier Limits
    static let freeCheckInsPerWeek = 5
    static let freeChatMessagesPerMonth = 10

    // MARK: - Check-in Defaults
    static let defaultCheckInTimes: [Int] = [8, 13, 18, 22] // hours
    static let taskReminderLeadMinutes = 30

    // MARK: - Patterns
    static let defaultPatternWindowDays = 30
    static let weeklyReviewDay = 1 // Sunday (Calendar weekday)
    static let weeklyReviewHour = 21 // 9 PM

    // MARK: - Keychain Keys
    static let anthropicAPIKeyKey = "com.myaissistant.anthropic-api-key"
    static let openAIAPIKeyKey = "com.myaissistant.openai-api-key"

    // MARK: - App Group
    static let appGroupID = "group.com.myaissistant.shared"

    // MARK: - StoreKit Product IDs
    enum ProductID {
        static let proMonthly = "com.myaissistant.pro.monthly"
        static let proAnnual = "com.myaissistant.pro.annual"
        static let studentMonthly = "com.myaissistant.student.monthly"
        static let studentAnnual = "com.myaissistant.student.annual"
        static let powerUserMonthly = "com.myaissistant.poweruser.monthly"
        static let powerUserAnnual = "com.myaissistant.poweruser.annual"
    }
}
