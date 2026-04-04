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
        modelContext.safeSave()
        return new
    }

    // MARK: - Gate Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
        let t = tracker()
        // If integrity fails (e.g. reinstall with new Keychain key), re-sign rather than blocking
        if !t.verifyIntegrity() {
            t.updateIntegrityHash()
            modelContext.safeSave()
        }
        return t.canSendChat(tier: tier)
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
        let t = tracker()
        if !t.verifyIntegrity() {
            t.updateIntegrityHash()
            modelContext.safeSave()
        }
        return t.canDoCheckIn(tier: tier)
    }

    // MARK: - Usage Info

    var remainingChatMessages: Int {
        if AppConstants.isDeveloperMode { return 999 }
        return tracker().remainingChatMessages
    }

    var remainingCheckIns: Int {
        if AppConstants.isDeveloperMode { return 999 }
        return tracker().remainingCheckIns
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
}
