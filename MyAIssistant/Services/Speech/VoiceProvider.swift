import Foundation

/// Represents a selectable voice from any TTS provider.
struct VoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    let accent: String
    let gender: VoiceGender
    let quality: VoiceQuality
    let provider: VoiceProviderType

    enum VoiceGender: String, CaseIterable {
        case female, male
    }

    enum VoiceQuality: Comparable {
        case standard, enhanced, premium
    }
}

enum VoiceProviderType: String, CaseIterable, Identifiable {
    case apple = "Apple"
    case edge = "Edge (Natural)"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .apple: return "Built-in device voices (works offline)"
        case .edge: return "Microsoft Neural voices (requires internet)"
        }
    }
}

@MainActor
protocol VoiceProvider {
    var providerType: VoiceProviderType { get }
    var isSpeaking: Bool { get }

    func speak(_ text: String, voiceID: String?) async
    func stop()
    func availableVoices() -> [VoiceOption]
}
