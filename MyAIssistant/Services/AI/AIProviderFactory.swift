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
    ///   1. **Signed in with Apple AND no BYOK key** → Thrivn backend (uses our Anthropic key, server-side quota)
    ///   2. **BYOK key set** → Direct AnthropicProvider with user's key (privacy mode, unlimited)
    ///   3. **OpenAI key set (powerUser only)** → Direct OpenAIProvider
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

        // 1. BYOK Anthropic key takes priority — if the user explicitly set their own key,
        //    they want to use it (privacy mode, unlimited usage on their dime).
        if let anthropicKey = keychain.anthropicAPIKey(), !anthropicKey.isEmpty {
            return AnthropicProvider(apiKey: anthropicKey, model: model)
        }

        // 2. PowerUser tier with OpenAI key — supported as a fallback for OpenAI users.
        if tier == .powerUser, let openAIKey = keychain.openAIAPIKey(), !openAIKey.isEmpty {
            return OpenAIProvider(apiKey: openAIKey)
        }

        // 3. Signed in with Apple → use Thrivn backend (uses our key, server-side quota)
        if keychain.read(key: AppConstants.thrivnRefreshTokenKey)?.isEmpty == false {
            return ThrivnBackendService(model: model, keychain: keychain)
        }

        // 4. Nothing configured — surface a clear error
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
