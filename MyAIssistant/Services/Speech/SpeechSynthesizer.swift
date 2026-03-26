import AVFoundation

@Observable
@MainActor
final class SpeechSynthesizer: NSObject, AVSpeechSynthesizerDelegate {
    var isSpeaking: Bool = false
    var onFinishedSpeaking: (() -> Void)?
    var selectedVoiceIdentifier: String?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        stop()

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true)
        try? audioSession.overrideOutputAudioPort(.speaker)

        let utterance = AVSpeechUtterance(string: text)

        if let voiceID = selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.bestAvailableVoice()
        }

        // Slightly slower than default with natural pitch for more conversational delivery
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = 1.05
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Voice Selection

    /// Returns the highest quality English voice available on the device.
    /// Prefers premium > enhanced > default quality.
    static func bestAvailableVoice() -> AVSpeechSynthesisVoice {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        // Try premium first, then enhanced
        if let premium = englishVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = englishVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US") ?? englishVoices.first
            ?? AVSpeechSynthesisVoice()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Deactivate audio session to fully stop speaker output before mic can start
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Task { @MainActor in
            self.isSpeaking = false
            self.onFinishedSpeaking?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
