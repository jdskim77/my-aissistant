import AVFoundation

@Observable
@MainActor
final class SpeechSynthesizer {
    var isSpeaking: Bool = false
    var onFinishedSpeaking: (() -> Void)?
    var selectedVoiceIdentifier: String?
    var selectedProviderType: VoiceProviderType = .apple

    private let appleProvider = AppleVoiceProvider()
    private let edgeProvider = EdgeVoiceProvider()

    private var activeProvider: VoiceProvider {
        switch selectedProviderType {
        case .apple: return appleProvider
        case .edge: return edgeProvider
        }
    }

    var currentProviderVoices: [VoiceOption] {
        activeProvider.availableVoices()
    }

    func speak(_ text: String) {
        let voiceID = selectedVoiceIdentifier
        isSpeaking = true

        Task {
            await activeProvider.speak(text, voiceID: voiceID)
            self.isSpeaking = false
            self.onFinishedSpeaking?()
        }
    }

    func stop() {
        appleProvider.stop()
        edgeProvider.stop()
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
