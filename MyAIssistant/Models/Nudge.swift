import Foundation
import SwiftData

/// A proactive coaching nudge: a short, specific, action-suggesting message produced
/// by `NudgeEngine` on app-foreground or daily BGTask, surfaced as a local notification
/// or in-app banner, and rated by the user's response.
///
/// CloudKit-compatible: no `@Attribute(.unique)`, every stored property has a default.
/// Enums are stored as `rawValue` strings with `@Transient` computed accessors so
/// `#Predicate` can filter on the raw fields.
@Model
final class Nudge {
    var id: String = UUID().uuidString
    var createdAt: Date = Date()

    /// nil = deliver immediately
    var scheduledFor: Date?
    var deliveredAt: Date?
    var respondedAt: Date?

    /// `NudgeCategory.rawValue` — both identifies the trigger rule and the category
    /// (one rule per category in v1).
    var categoryRaw: String = NudgeCategory.weakDimension.rawValue

    /// JSON blob of the inputs that fired the rule. Audit trail for eval harness.
    var triggerContextJSON: String = "{}"

    /// Visible copy.
    var bodyText: String = ""

    /// `NudgeAction.rawValue`.
    var suggestedActionRaw: String = NudgeAction.none.rawValue

    /// Optional payload for the action (e.g. task title to pre-fill, duration, etc.).
    var suggestedActionPayload: String?

    /// `LifeDimension.rawValue` — nil for general nudges.
    var dimensionRaw: String?

    /// `NudgeStatus.rawValue`.
    var statusRaw: String = NudgeStatus.pending.rawValue

    /// `UserNudgeResponse.rawValue` — nil until user interacts.
    var userResponseRaw: String?

    // MARK: - Transient accessors

    @Transient
    var category: NudgeCategory {
        get { NudgeCategory(rawValue: categoryRaw) ?? .weakDimension }
        set { categoryRaw = newValue.rawValue }
    }

    @Transient
    var action: NudgeAction {
        get { NudgeAction(rawValue: suggestedActionRaw) ?? .none }
        set { suggestedActionRaw = newValue.rawValue }
    }

    @Transient
    var status: NudgeStatus {
        get { NudgeStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    @Transient
    var userResponse: UserNudgeResponse? {
        get {
            guard let userResponseRaw else { return nil }
            return UserNudgeResponse(rawValue: userResponseRaw)
        }
        set { userResponseRaw = newValue?.rawValue }
    }

    @Transient
    var dimension: LifeDimension? {
        get {
            guard let dimensionRaw else { return nil }
            return LifeDimension(rawValue: dimensionRaw)
        }
        set { dimensionRaw = newValue?.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        scheduledFor: Date? = nil,
        category: NudgeCategory,
        triggerContextJSON: String = "{}",
        bodyText: String,
        action: NudgeAction = .none,
        suggestedActionPayload: String? = nil,
        dimension: LifeDimension? = nil,
        status: NudgeStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.scheduledFor = scheduledFor
        self.categoryRaw = category.rawValue
        self.triggerContextJSON = triggerContextJSON
        self.bodyText = bodyText
        self.suggestedActionRaw = action.rawValue
        self.suggestedActionPayload = suggestedActionPayload
        self.dimensionRaw = dimension?.rawValue
        self.statusRaw = status.rawValue
    }
}

// MARK: - Enums

enum NudgeCategory: String, Codable, CaseIterable {
    case weakDimension
    case streakAtRisk
    case calendarGap
    case habitSlip
    case postCheckInAction
    case goalCheckpoint
    /// Uncompleted habit currently in its time-window and past the window's
    /// midpoint. Distinct from `habitSlip` (multi-day miss streak) — this
    /// fires *within* the window, before the day is lost.
    case windowedHabit
    /// Safety-route nudge emitted when the on-device crisis classifier flags
    /// the most recent check-in / chat text. Copy is hardcoded
    /// (see `SafeResourceCopy`), never LLM-generated, and never silenceable
    /// via the Coach Settings category list. Bypasses daily caps and quiet
    /// hours — respects only the 24h safety pause that follows its delivery.
    case safetyRoute
}

enum NudgeAction: String, Codable, CaseIterable {
    case createTask
    case startFocusTimer
    case openCheckIn
    case openChat
    case none
}

enum NudgeStatus: String, Codable, CaseIterable {
    case pending
    case delivered
    case responded
    case expired
    case suppressed
}

enum UserNudgeResponse: String, Codable, CaseIterable {
    case accepted
    case dismissed
    case snoozed
    case ignored
    case silenced
}
