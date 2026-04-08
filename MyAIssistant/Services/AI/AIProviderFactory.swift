import Foundation

enum SubscriptionTier: String {
    case free
    case pro
    case student
    case powerUser
}

enum AIUseCase {
    case chat
    case checkIn
    case weeklyReview
}

enum AIProviderFactory {

    /// Returns the appropriate AI provider and model for the given tier and use case.
    ///
    /// Resolution priority (in order):
    ///   1. **Signed in with Apple** → Thrivn backend (server-side quota, our Anthropic key)
    ///   2. **BYOK Anthropic key** → Direct AnthropicProvider with user's key (privacy mode)
    ///   3. **PowerUser + OpenAI key** → Direct OpenAIProvider
    ///   4. **Nothing configured** → throws `noAPIKey`
    ///
    /// Note: The backend takes priority over BYOK for signed-in users to ensure server-side
    /// quota tracking and consistent cost accounting. Users who want to use their own key
    /// can sign out (which deletes the refresh token) and then enter a BYOK key.
    ///
    /// - Parameters:
    ///   - tier: The user's subscription tier
    ///   - useCase: What the AI will be used for
    ///   - keychain: Keychain service for retrieving API keys
    static func provider(
        for tier: SubscriptionTier,
        useCase: AIUseCase,
        keychain: KeychainService
    ) throws -> any AIProvider {
        let model = modelFor(tier: tier, useCase: useCase)

        // 1. Signed in with Apple → use Thrivn backend (uses our key, server-side quota).
        //    This is the default path for new users who completed onboarding.
        if let refresh = keychain.read(key: AppConstants.thrivnRefreshTokenKey),
           !refresh.isEmpty {
            return ThrivnBackendService(model: model, keychain: keychain)
        }

        // 2. BYOK Anthropic key — privacy mode for users who skipped sign-in or signed out.
        if let anthropicKey = keychain.anthropicAPIKey(), !anthropicKey.isEmpty {
            return AnthropicProvider(apiKey: anthropicKey, model: model)
        }

        // 3. PowerUser tier with OpenAI key — fallback for OpenAI users.
        if tier == .powerUser, let openAIKey = keychain.openAIAPIKey(), !openAIKey.isEmpty {
            return OpenAIProvider(apiKey: openAIKey)
        }

        // 4. Nothing configured — surface a clear error.
        throw AIError.noAPIKey
    }

    /// Picks the appropriate model based on tier + use case.
    private static func modelFor(tier: SubscriptionTier, useCase: AIUseCase) -> String {
        switch tier {
        case .free:
            return AppConstants.haikuModel
        case .pro, .student:
            switch useCase {
            case .chat, .weeklyReview:
                return AppConstants.sonnetModel
            case .checkIn:
                return AppConstants.haikuModel
            }
        case .powerUser:
            return AppConstants.sonnetModel
        }
    }
}
