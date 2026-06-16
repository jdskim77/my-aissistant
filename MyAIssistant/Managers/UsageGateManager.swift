import Foundation
import Observation
import SwiftData

// MARK: - Engine / Reusable
//
// Tier-aware usage metering layer. Wraps a per-device `UsageTracker` with
// subscription-tier-aware checks (free tier has monthly quotas; paid tiers
// are unlimited). Domain-neutral — the thing being metered is opaque at this
// layer (the tracker counts arbitrary events).
//
// Reusable: yes, in any app with a free-tier quota + StoreKit subscriptions.
// Dependencies: SwiftData (UsageTracker model), SubscriptionManager.
// Watch-compatible: no (iOS-only, uses shared CloudKit store).
//
// Fork notes:
// - `UsageTracker` is persisted via SwiftData and must be in the schema.
// - Per-device scoping (deviceID) prevents one device's tracker from locking
//   out another on the same iCloud account. Preserve this in any fork.
// - Real per-account enforcement happens server-side (the on-device tracker
//   is advisory). If the fork has no backend, document that upfront.
/// Enforces tier-based usage limits. Wraps UsageTracker with tier-aware checks.
@Observable @MainActor
final class UsageGateManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch or Create Tracker

    /// Fetches the usage tracker for THIS device. The store is CloudKit-synced
    /// across devices on the same iCloud account, so multiple devices each have
    /// their own row scoped by `deviceID`. Without this scoping, `.first` could
    /// return another device's row (with a mismatched HMAC integrity key) and
    /// permanently lock the user out of chat. Real per-account limits are still
    /// enforced server-side by the backend.
    private func tracker() -> UsageTracker {
        let myDeviceID = UsageTracker.currentDeviceID()
        let descriptor = FetchDescriptor<UsageTracker>(
            predicate: #Predicate { $0.deviceID == myDeviceID }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        // Migration: existing pre-deviceID rows have an empty deviceID. Adopt
        // the first orphan row as this device's row instead of creating a new one.
        let orphanDescriptor = FetchDescriptor<UsageTracker>(
            predicate: #Predicate { $0.deviceID == "" }
        )
        if let orphan = try? modelContext.fetch(orphanDescriptor).first {
            orphan.deviceID = myDeviceID
            modelContext.safeSave()
            return orphan
        }
        let new = UsageTracker()
        modelContext.insert(new)
        modelContext.safeSave()
        return new
    }

    // MARK: - Gate Checks

    func canSendChat(tier: SubscriptionTier) -> Bool {
        // Absolute daily-input-token ceiling — applies first, before the
        // beta / developer bypass. Without this, an exposed BYOK key plus
        // `isBetaUnlimited == true` (the current production state) means
        // there's no client-side ceiling on AI spend. The cap is high
        // enough not to trip legitimate workloads but stops runaway abuse.
        if Self.absoluteDailyInputTokens() >= AppConstants.absoluteDailyInputTokenCeiling {
            AppLogger.ai.warning("Absolute daily input-token ceiling reached — chat blocked for the rest of today")
            return false
        }
        // Developer mode + beta period bypass everything ELSE, including
        // integrity checks. Otherwise CloudKit cross-device HMAC mismatches
        // could lock beta testers out of chat with no recovery path.
        if AppConstants.isDeveloperMode { return true }
        let t = tracker()
        guard t.verifyIntegrity() else { return false }
        return t.canSendChat(tier: tier)
    }

    // MARK: - Absolute daily token ceiling

    /// UserDefaults-backed: a `[dateString: tokenCount]` keyed by today's
    /// `yyyy-MM-dd`. We intentionally store a single-key dictionary instead
    /// of just an Int so a stale value from yesterday auto-clears on read.
    private static func todayKey() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func absoluteDailyInputTokens() -> Int {
        let bucket = UserDefaults.standard.dictionary(forKey: AppConstants.absoluteDailyTokenBucketKey) as? [String: Int] ?? [:]
        return bucket[todayKey()] ?? 0
    }

    static func incrementAbsoluteDailyInputTokens(by tokens: Int) {
        guard tokens > 0 else { return }
        let key = todayKey()
        // Replace the whole dictionary with a single entry — yesterday's
        // entry is the one cleanup we need.
        let current = (UserDefaults.standard.dictionary(forKey: AppConstants.absoluteDailyTokenBucketKey) as? [String: Int])?[key] ?? 0
        UserDefaults.standard.set([key: current + tokens], forKey: AppConstants.absoluteDailyTokenBucketKey)
    }

    func canDoCheckIn(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
        let t = tracker()
        guard t.verifyIntegrity() else { return false }
        return t.canDoCheckIn(tier: tier)
    }

    func canSuggestGoalTasks(tier: SubscriptionTier) -> Bool {
        if AppConstants.isDeveloperMode { return true }
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

    func recordChatMessage(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int? = nil,
        cacheReadTokens: Int? = nil
    ) {
        // Anthropic prices: cache write ~125% of input, cache read ~10% of input.
        // Collapse the cache counters into an effective input value so cost dashboards
        // don't under-report once caching engages. Avoids a UsageTracker schema bump.
        let creation = Double(cacheCreationTokens ?? 0)
        let read = Double(cacheReadTokens ?? 0)
        let effectiveInput = inputTokens + Int((creation * 1.25).rounded()) + Int((read * 0.10).rounded())
        let t = tracker()
        t.recordChatMessage(inputTokens: effectiveInput, outputTokens: outputTokens)
        modelContext.safeSave()

        // Bump the absolute daily ceiling — this counter is the only one
        // that survives `isBetaUnlimited` / developer mode, so it must
        // increment regardless of tier path.
        Self.incrementAbsoluteDailyInputTokens(by: effectiveInput)
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
