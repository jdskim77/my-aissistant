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
    static let freeCheckInsPerDay = 4
    static let freeCheckInsPerDayNewUser = 10
    static let newUserGracePeriodDays = 3
    static let freeChatMessagesPerMonth = 10
    static let freeGoalSuggestionsPerWeek = 3

    // MARK: - Beta Period
    /// Beta period flag — when true, all usage limits are disabled for testers.
    /// Set to false before App Store public release to re-enable free-tier limits.
    /// One-line revert: change `true` to `false`, rebuild, ship.
    static let isBetaUnlimited = true

    // MARK: - Developer Mode
    static let developerModeKey = "developerModeEnabled"

    /// Returns true if developer mode is active — bypasses all usage limits.
    /// Also returns true during the beta period (`isBetaUnlimited`) so testers
    /// have unlimited chat messages, check-ins, tasks, and goal suggestions.
    static var isDeveloperMode: Bool {
        if isBetaUnlimited { return true }
        return UserDefaults.standard.bool(forKey: developerModeKey)
    }

    /// Returns true ONLY if the user explicitly enabled developer mode via the
    /// 7-tap gesture in Settings. Ignores `isBetaUnlimited`. Use this to gate
    /// destructive developer tools (Wipe Data, Reset Onboarding) so beta
    /// testers don't see them by default — only the developer does.
    static var isDeveloperToolsEnabled: Bool {
        UserDefaults.standard.bool(forKey: developerModeKey)
    }

    // MARK: - Check-in Defaults
    static let defaultCheckInTimes: [Int] = [8, 13, 18, 22] // hours
    static let taskReminderLeadMinutes = 30

    // MARK: - Adaptive Check-in Behavior
    static let behaviorWindowDays = 14
    static let quietAdjustMaxMinutes = 30
    static let suggestionCooldownDays = 30
    static let disableThreshold = 0.25
    static let organicClusterMinCount = 5
    static let timeDriftThresholdMinutes = 15
    static let minWindowSpacingMinutes = 30

    // MARK: - Patterns
    static let defaultPatternWindowDays = 30
    static let weeklyReviewDay = 1 // Sunday (Calendar weekday)
    static let weeklyReviewHour = 21 // 9 PM

    // MARK: - Keychain Keys
    static let anthropicAPIKeyKey = "com.myaissistant.anthropic-api-key"
    static let openAIAPIKeyKey = "com.myaissistant.openai-api-key"

    // MARK: - Thrivn Backend
    static let thrivnBackendURL = "https://thrivn-api.jdskim77.workers.dev"
    static let thrivnAccessTokenKey = "com.myaissistant.thrivn-access-token"
    static let thrivnRefreshTokenKey = "com.myaissistant.thrivn-refresh-token"
    static let thrivnUserIDKey = "com.myaissistant.thrivn-user-id"
    static let hasSignedInWithAppleKey = "hasSignedInWithApple"

    // MARK: - UserDefaults Keys (Voice)
    static let voiceModeDefaultKey = "voiceModeDefault"
    static let selectedVoiceIDKey = "selectedVoiceID"
    static let voiceProviderKey = "voiceProvider"

    // MARK: - UserDefaults Keys (Theme)
    static let appThemeKey = "appTheme"

    // MARK: - UserDefaults Keys (Text Size)
    static let textSizeKey = "textSize"

    // MARK: - Google Calendar
    // Public OAuth client ID — bound to bundle ID, not a secret per Google's mobile OAuth spec
    static let googleClientID = "124674263612-m8h7hifl06m3ru01k3fvtbmmjleoatfp.apps.googleusercontent.com"
    static let googleClientIDKey = "googleClientID"

    // MARK: - Streak Notifications
    static let streakReminderHour = 20 // 8 PM
    static let streakReminderIdentifier = "streak-at-risk"
    static let notificationFrequencyKey = "notificationFrequency"
    static let moderateStreakThreshold = 8
    static let minimalStreakThreshold = 22

    // MARK: - Keychain Keys (Google Calendar)
    static let googleAccessTokenKey = "com.myaissistant.google-access-token"
    static let googleRefreshTokenKey = "com.myaissistant.google-refresh-token"
    static let googleTokenExpiryKey = "com.myaissistant.google-token-expiry"

    // MARK: - UserDefaults Keys (Greeting)
    static let lastGreetedTimestampKey = "lastGreetedTimestamp"
    static let lastGreetingTextKey = "lastGreetingText"

    // MARK: - Feedback
    /// Beta feedback Google Form (anonymous, structured questions).
    /// Used while `isBetaUnlimited == true`.
    static let feedbackGoogleFormURL = "https://forms.gle/ZiS7R5kGBYi7poJ6A"

    /// Public support email (Apple Hide My Email forwarding alias — anonymous,
    /// can be disabled instantly if abused). Used after public release.
    static let supportEmail = "t5rwp4dwgh@privaterelay.appleid.com"

    // MARK: - App Group
    static let appGroupID = "group.com.myaissistant.shared"

    // MARK: - iCloud
    static let cloudKitContainerID = "iCloud.com.myaissistant"

    // MARK: - Nudge Engine (Phase 1 scaffolding)

    /// BGTask identifier for daily nudge evaluation. Must also be listed in
    /// Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static let nudgeEvaluationBGTaskID = "com.myaissistant.nudge-evaluation"

    /// Kill switch — when true the engine evaluates nothing and delivers no
    /// nudges. Phase 1 defaulted this to true (scaffolding only). Phase 2
    /// flips it to false so the first live rule (`WeakDimensionWithOpenWindowRule`)
    /// can fire. Flipping back to true remains the emergency kill for
    /// bad-behavior regressions between TestFlight builds.
    static let nudgeEngineKillSwitchEnabled = false

    /// Hard frequency caps (spec §7.1).
    static let nudgeMaxPerDay = 2
    static let nudgeMinHoursBetween = 1
    static let nudgeDefaultCooldownHours = 48
    static let nudgeStreakAtRiskCooldownHours = 24
    /// Bumped 72 → 96 for Phase 2 so the same dimension doesn't resurface
    /// within four days — conservative cadence for external testers.
    static let nudgeWeakDimensionCooldownHours = 96
    static let nudgeMaxPerDimensionHours = 48

    /// Phase 2 weak-dimension rule tunables.
    ///
    /// `nudgeBaselineMinDays`: minimum ritual streak before dimension-weakness
    /// nudges can fire — avoids framing noise as a deficit for brand-new users.
    /// `nudgeMinOpenWindowMinutes`: minimum calendar gap the rule considers
    /// "usable" — 30 is generous enough for a real act, not a manufactured break.
    /// `nudgeWeakDimensionQuintileCeiling`: a dimension must score at or below
    /// this (0-100 scale) to be considered "quiet." 20 = bottom quintile.
    static let nudgeBaselineMinDays = 14
    static let nudgeMinOpenWindowMinutes = 30
    static let nudgeWeakDimensionQuintileCeiling = 20

    /// Quiet-hours defaults (spec §7.2).
    static let nudgeQuietHoursStartHour = 21 // 9 PM
    static let nudgeQuietHoursEndHour = 8    // 8 AM

    /// UserDefaults keys for user-facing tuning (Settings → Coach).
    static let nudgeEnabledKey = "coach.nudge.enabled"
    static let nudgeFrequencyKey = "coach.nudge.frequency" // "gentle" / "balanced" / "off"
    static let nudgeQuietHoursStartKey = "coach.nudge.quietStart"
    static let nudgeQuietHoursEndKey = "coach.nudge.quietEnd"
    static let nudgeSilencedCategoriesKey = "coach.nudge.silencedCategories"

    /// Notification category for inline actions.
    static let nudgeNotificationCategory = "NUDGE_CATEGORY"
    static let nudgeAcceptActionID = "NUDGE_ACCEPT"
    static let nudgeDismissActionID = "NUDGE_DISMISS"
    static let nudgeSnoozeActionID = "NUDGE_SNOOZE"
    static let nudgeSilenceActionID = "NUDGE_SILENCE"

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
