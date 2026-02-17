import Foundation
import SwiftData

/// Enforces tier-based usage limits. Wraps UsageTracker with tier-aware checks.
@MainActor
final class UsageGateManager: ObservableObject {
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
        try? modelContext.save()
        return new
    }

    // MARK: - Gate Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        tracker().canSendChat(tier: tier)
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        tracker().canDoCheckIn(tier: tier)
    }

    // MARK: - Usage Info

    var remainingChatMessages: Int {
        tracker().remainingChatMessages
    }

    var remainingCheckIns: Int {
        tracker().remainingCheckIns
    }

    var chatUsedThisMonth: Int {
        tracker().chatMessagesThisMonth
    }

    var checkInsUsedThisWeek: Int {
        tracker().checkInsThisWeek
    }

    // MARK: - Recording

    func recordChatMessage(inputTokens: Int, outputTokens: Int) {
        let t = tracker()
        t.recordChatMessage(inputTokens: inputTokens, outputTokens: outputTokens)
        try? modelContext.save()
    }

    func recordCheckIn() {
        let t = tracker()
        t.recordCheckIn()
        try? modelContext.save()
    }
}
