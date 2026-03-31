import AVFoundation

@Observable
@MainActor
final class EdgeVoiceProvider: VoiceProvider {
    let providerType: VoiceProviderType = .edge
    var isSpeaking: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private var speakingTask: Task<Void, Never>?

    /// Curated list of natural-sounding Edge Neural voices.
    static let edgeVoices: [VoiceOption] = [
        // Female - American
        VoiceOption(id: "en-US-JennyNeural", name: "Jenny", accent: "American", gender: .female, quality: .premium, provider: .edge),
        VoiceOption(id: "en-US-AriaNeural", name: "Aria", accent: "American", gender: .female, quality: .premium, provider: .edge),
        VoiceOption(id: "en-US-SaraNeural", name: "Sara", accent: "American", gender: .female, quality: .enhanced, provider: .edge),
        // Male - American
        VoiceOption(id: "en-US-GuyNeural", name: "Guy", accent: "American", gender: .male, quality: .premium, provider: .edge),
        VoiceOption(id: "en-US-ChristopherNeural", name: "Christopher", accent: "American", gender: .male, quality: .enhanced, provider: .edge),
        VoiceOption(id: "en-US-EricNeural", name: "Eric", accent: "American", gender: .male, quality: .enhanced, provider: .edge),
        // Female - British
        VoiceOption(id: "en-GB-SoniaNeural", name: "Sonia", accent: "British", gender: .female, quality: .premium, provider: .edge),
        VoiceOption(id: "en-GB-LibbyNeural", name: "Libby", accent: "British", gender: .female, quality: .enhanced, provider: .edge),
        VoiceOption(id: "en-GB-MaisieNeural", name: "Maisie", accent: "British", gender: .female, quality: .enhanced, provider: .edge),
        // Male - British
        VoiceOption(id: "en-GB-RyanNeural", name: "Ryan", accent: "British", gender: .male, quality: .premium, provider: .edge),
        VoiceOption(id: "en-GB-ThomasNeural", name: "Thomas", accent: "British", gender: .male, quality: .enhanced, provider: .edge),
        // Female - Australian
        VoiceOption(id: "en-AU-NatashaNeural", name: "Natasha", accent: "Australian", gender: .female, quality: .premium, provider: .edge),
        // Male - Australian
        VoiceOption(id: "en-AU-WilliamNeural", name: "William", accent: "Australian", gender: .male, quality: .premium, provider: .edge),
        // Female - Indian
        VoiceOption(id: "en-IN-NeerjaNeural", name: "Neerja", accent: "Indian", gender: .female, quality: .premium, provider: .edge),
        // Male - Indian
        VoiceOption(id: "en-IN-PrabhatNeural", name: "Prabhat", accent: "Indian", gender: .male, quality: .enhanced, provider: .edge),
        // Female - Irish
        VoiceOption(id: "en-IE-EmilyNeural", name: "Emily", accent: "Irish", gender: .female, quality: .enhanced, provider: .edge),
        // Male - Irish
        VoiceOption(id: "en-IE-ConnorNeural", name: "Connor", accent: "Irish", gender: .male, quality: .enhanced, provider: .edge),
    ]

    func speak(_ text: String, voiceID: String?) async {
        stop()

        let voice = voiceID ?? "en-US-JennyNeural"
        isSpeaking = true

        speakingTask = Task {
            do {
                let audioData = try await fetchEdgeAudio(text: text, voice: voice)
                guard !Task.isCancelled else { return }
                try await playAudio(audioData)
            } catch {
                if !Task.isCancelled {
                    print("EdgeTTS error: \(error.localizedDescription)")
                }
            }
            if !Task.isCancelled {
                self.isSpeaking = false
            }
        }

        await speakingTask?.value
    }

    func stop() {
        speakingTask?.cancel()
        speakingTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func availableVoices() -> [VoiceOption] {
        Self.edgeVoices
    }

    // MARK: - Edge TTS WebSocket

    private func fetchEdgeAudio(text: String, voice: String) async throws -> Data {
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let timestamp = ISO8601DateFormatter().string(from: Date())

        let wsURL = URL(string:
            "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
            + "?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4"
            + "&ConnectionId=\(token)"
        )!

        let session = URLSession(configuration: .default)
        let wsTask = session.webSocketTask(with: wsURL)
        wsTask.resume()

        // Send config
        let configMessage =
            "X-Timestamp:\(timestamp)\r\n"
            + "Content-Type:application/json; charset=utf-8\r\n"
            + "Path:speech.config\r\n\r\n"
            + "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}"

        try await wsTask.send(.string(configMessage))

        // Send SSML
        let ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
            + "<voice name='\(voice)'>"
            + "<prosody pitch='+0Hz' rate='+0%' volume='+0%'>"
            + escapeXML(text)
            + "</prosody></voice></speak>"

        let ssmlMessage =
            "X-RequestId:\(token)\r\n"
            + "Content-Type:application/ssml+xml\r\n"
            + "X-Timestamp:\(timestamp)\r\n"
            + "Path:ssml\r\n\r\n"
            + ssml

        try await wsTask.send(.string(ssmlMessage))

        // Receive audio chunks
        var audioData = Data()

        while !Task.isCancelled {
            let message = try await wsTask.receive()
            switch message {
            case .data(let data):
                // Binary messages contain a 2-byte header length prefix followed by headers, then audio
                guard data.count > 2 else { continue }
                let headerLen = Int(data[0]) << 8 | Int(data[1])
                let audioStart = 2 + headerLen
                if audioStart < data.count {
                    audioData.append(data[audioStart...])
                }
            case .string(let text):
                if text.contains("Path:turn.end") {
                    break
                }
                continue
            @unknown default:
                continue
            }
            // Check if we got turn.end in the last string message
            if case .string(let text) = message, text.contains("Path:turn.end") {
                break
            }
        }

        wsTask.cancel(with: .goingAway, reason: nil)
        return audioData
    }

    private func playAudio(_ data: Data) async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .default)
        try audioSession.setActive(true)
        try audioSession.overrideOutputAudioPort(.speaker)

        audioPlayer = try AVAudioPlayer(data: data)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()

        // Wait for playback to finish
        while let player = audioPlayer, player.isPlaying, !Task.isCancelled {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
