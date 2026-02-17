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
    /// - Parameters:
    ///   - tier: The user's subscription tier
    ///   - useCase: What the AI will be used for
    ///   - keychain: Keychain service for retrieving API keys
    /// - Returns: An AIProvider configured with the correct model
    static func provider(
        for tier: SubscriptionTier,
        useCase: AIUseCase,
        keychain: KeychainService
    ) throws -> any AIProvider {
        switch tier {
        case .free:
            return try anthropicProvider(model: AppConstants.haikuModel, keychain: keychain)

        case .pro, .student:
            let model: String
            switch useCase {
            case .chat, .weeklyReview:
                model = AppConstants.sonnetModel
            case .checkIn:
                model = AppConstants.haikuModel
            }
            return try anthropicProvider(model: model, keychain: keychain)

        case .powerUser:
            // BYOK: prefer user's OpenAI key if set, fall back to Anthropic
            if let openAIKey = keychain.openAIAPIKey(), !openAIKey.isEmpty {
                return OpenAIProvider(apiKey: openAIKey)
            }
            return try anthropicProvider(model: AppConstants.sonnetModel, keychain: keychain)
        }
    }

    private static func anthropicProvider(model: String, keychain: KeychainService) throws -> AnthropicProvider {
        guard let apiKey = keychain.anthropicAPIKey(), !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }
        return AnthropicProvider(apiKey: apiKey, model: model)
    }
}
