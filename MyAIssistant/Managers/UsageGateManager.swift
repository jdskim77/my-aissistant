import Foundation
import Observation
import SwiftData

/// Enforces tier-based usage limits. Wraps UsageTracker with tier-aware checks.
@Observable @MainActor
final class UsageGateManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch or Create Tracker

    private func tracker() -> UsageTracker {
        let descriptor = FetchDescriptor<UsageTracker>()
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let new = UsageTracker()
        modelContext.insert(new)
        modelContext.safeSave()
        return new
    }

    // MARK: - Gate Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        let t = tracker()
        guard t.verifyIntegrity() else { return false }
        return t.canSendChat(tier: tier)
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        let t = tracker()
        guard t.verifyIntegrity() else { return false }
        return t.canDoCheckIn(tier: tier)
    }

    func canSuggestGoalTasks(tier: SubscriptionTier) -> Bool {
        let t = tracker()
        guard t.verifyIntegrity() else { return false }
        return t.canSuggestGoalTasks(tier: tier)
    }

    // MARK: - Usage Info

    var remainingChatMessages: Int {
        tracker().remainingChatMessages
    }

    var remainingCheckIns: Int {
        tracker().remainingCheckIns
    }

    var remainingGoalSuggestions: Int {
        tracker().remainingGoalSuggestions
    }

    var chatUsedThisMonth: Int {
        tracker().chatMessagesThisMonth
    }

    var checkInsUsedToday: Int {
        tracker().checkInsToday
    }

    // MARK: - Recording

    func recordChatMessage(inputTokens: Int, outputTokens: Int) {
        let t = tracker()
        t.recordChatMessage(inputTokens: inputTokens, outputTokens: outputTokens)
        modelContext.safeSave()
    }

    func recordCheckIn() {
        let t = tracker()
        t.recordCheckIn()
        modelContext.safeSave()
    }

    func recordGoalSuggestion() {
        let t = tracker()
        t.recordGoalSuggestion()
        modelContext.safeSave()
    }
}
