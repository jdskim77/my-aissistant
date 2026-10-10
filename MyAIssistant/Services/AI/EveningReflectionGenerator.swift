import Foundation
import OSLog

/// Evening Flow redesign: generates the ONE coach reflection sent to the
/// Coach tab right after the user saves their night check-in. The
/// reflection references tonight's ratings, is honest and specific, never
/// cheerleads, and is gated behind an on/off setting plus AI/sign-in
/// availability.
///
/// Trigger-once guarantee lives in the caller (`EveningCheckInView`), which
/// only calls `send` from the "Save check-in" action path, once per
/// check-in session.
@MainActor
final class EveningReflectionGenerator {
    private let keychainService: KeychainService
    weak var chatManager: ChatManager?

    /// The conversation ID used for evening-reflection messages — same
    /// conversation as the main Coach chat so the reflection reads as a
    /// continuation of an ongoing relationship, not a separate thread.
    static let conversationID = "main"

    init(keychainService: KeychainService, chatManager: ChatManager?) {
        self.keychainService = keychainService
        self.chatManager = chatManager
    }

    /// Sends one reflection referencing tonight's ratings. Silently no-ops
    /// (no error bubble, caller just lands on Coach) when:
    ///   - the setting is off,
    ///   - the user is signed out / has no API key (AIProviderFactory throws),
    ///   - or generation otherwise fails.
    /// Never throws — callers never need to special-case failure UI.
    func send(
        ratings: [LifeDimension: Int],
        energyRating: Int?,
        subscriptionTier: SubscriptionTier
    ) async {
        guard AppConstants.eveningReflectionHandoffEnabled else { return }

        let stringRatings: [String: Int] = ratings.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        let prompt = AIPromptBuilder.eveningReflectionPrompt(
            ratings: stringRatings,
            energyRating: energyRating
        )

        do {
            let provider = try AIProviderFactory.provider(
                for: subscriptionTier,
                useCase: .checkIn,
                keychain: keychainService
            )
            let response = try await provider.sendMessage(
                userMessage: "Generate tonight's reflection.",
                conversationHistory: [],
                systemPromptStable: prompt,
                systemPromptVolatile: ""
            )
            let reflection = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reflection.isEmpty else { return }
            chatManager?.insertLocalMessage(
                role: .assistant,
                content: reflection,
                conversationID: Self.conversationID
            )
        } catch {
            // AI unavailable or user signed out — land on Coach silently,
            // no error bubble (product rule).
            AppLogger.ai.info("Evening reflection skipped: \(error.localizedDescription, privacy: .public)")
        }
    }
}
