import Foundation

enum AppConstants {
    // MARK: - API Endpoints
    static let anthropicEndpoint = "https://api.anthropic.com/v1/messages"
    static let anthropicAPIVersion = "2023-06-01"

    // MARK: - AI Models
    static let haikuModel = "claude-haiku-4-5-20251001"
    static let sonnetModel = "claude-sonnet-4-5-20250929"
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

    // MARK: - UserDefaults Keys (Voice)
    static let voiceModeDefaultKey = "voiceModeDefault"
    static let selectedVoiceIDKey = "selectedVoiceID"
    static let voiceProviderKey = "voiceProvider"

    // MARK: - UserDefaults Keys (Theme)
    static let appThemeKey = "appTheme"

    // MARK: - UserDefaults Keys (Text Size)
    static let textSizeKey = "textSize"

    // MARK: - Google Calendar
    static let googleClientID = "124674263612-m8h7hifl06m3ru01k3fvtbmmjleoatfp.apps.googleusercontent.com"
    static let googleClientIDKey = "googleClientID"

    // MARK: - Keychain Keys (Google Calendar)
    static let googleAccessTokenKey = "com.myaissistant.google-access-token"
    static let googleRefreshTokenKey = "com.myaissistant.google-refresh-token"
    static let googleTokenExpiryKey = "com.myaissistant.google-token-expiry"

    // MARK: - UserDefaults Keys (Greeting)
    static let lastGreetedTimestampKey = "lastGreetedTimestamp"
    static let lastGreetingTextKey = "lastGreetingText"

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
