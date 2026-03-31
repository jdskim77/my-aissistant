import AVFoundation

@Observable
@MainActor
final class AppleVoiceProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    let providerType: VoiceProviderType = .apple
    var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var speakingContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voiceID: String?) async {
        stop()

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true)
        try? audioSession.overrideOutputAudioPort(.speaker)

        let utterance = AVSpeechUtterance(string: text)

        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.bestAvailableVoice()
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0

        isSpeaking = true
        await withCheckedContinuation { continuation in
            speakingContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakingContinuation?.resume()
        speakingContinuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func availableVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .map { voice in
                VoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    accent: accentLabel(for: voice.language),
                    gender: voice.gender == .male ? .male : .female,
                    quality: mapQuality(voice.quality),
                    provider: .apple
                )
            }
            .sorted { $0.quality > $1.quality }
    }

    // MARK: - Helpers

    static func bestAvailableVoice() -> AVSpeechSynthesisVoice {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        if let premium = englishVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = englishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US") ?? englishVoices.first
            ?? AVSpeechSynthesisVoice()
    }

    private func mapQuality(_ quality: AVSpeechSynthesisVoiceQuality) -> VoiceOption.VoiceQuality {
        switch quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }

    private func accentLabel(for language: String) -> String {
        switch language {
        case "en-US": return "American"
        case "en-GB": return "British"
        case "en-AU": return "Australian"
        case "en-IN": return "Indian"
        case "en-IE": return "Irish"
        case "en-ZA": return "South African"
        case "en-SG": return "Singaporean"
        default: return language
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingContinuation?.resume()
            self.speakingContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingContinuation?.resume()
            self.speakingContinuation = nil
        }
    }
}
