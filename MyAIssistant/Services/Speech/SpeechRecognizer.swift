import Speech
import AVFoundation

// MARK: - Engine / Reusable (CLEAN)
//
// On-device speech recognition wrapper. Domain-neutral — transcribes audio
// to a `transcript` string. Caller decides what to do with it.
//
// Reusable: yes, in any app needing voice input.
// Dependencies: Speech, AVFoundation.
// Watch-compatible: limited — Watch has its own speech APIs and constraints
//   (see WatchVoiceChatView for the Watch-side voice flow).
//
// Fork notes:
// - Microphone + speech permission strings must be in Info.plist
//   (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).

@Observable
@MainActor
final class SpeechRecognizer {
    var transcript: String = ""
    var isRecording: Bool = false
    var errorMessage: String?
    var permissionGranted: Bool = false
    var onSilenceDetected: (() -> Void)?
    var silenceTimeout: TimeInterval = 1.5

    /// Minimum time the mic stays on before silence detection can stop it.
    var minimumRecordingDuration: TimeInterval = 2.0

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var silenceTimer: Timer?

    /// Tracks the start time of the current recording session.
    private var recordingStartTime: Date?

    /// Session generation counter — prevents stale callbacks from killing new sessions.
    private var sessionID: UInt = 0

    func requestPermission() async {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()

        permissionGranted = (speechStatus == .authorized && micGranted)
        if !permissionGranted {
            errorMessage = "Speech recognition requires microphone and speech permissions."
        }
    }

    func startRecording() throws {
        // If already recording, don't start a second session
        guard !isRecording else { return }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available on this device."
            return
        }

        // Bump session ID so stale callbacks from previous sessions are ignored
        sessionID &+= 1
        let currentSession = sessionID

        // Reset
        transcript = ""
        errorMessage = nil
        invalidateSilenceTimer()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        try audioSession.overrideOutputAudioPort(.speaker)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Privacy + offline: prefer on-device recognition when the device supports
        // it (A12+ with the en-US model installed). Audio never leaves the phone
        // in this path. Falls back to Apple's cloud transcription on older devices
        // or when the on-device model isn't yet downloaded.
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        recordingStartTime = Date()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == currentSession else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString

                    // Only start silence timer after minimum duration has elapsed
                    if !self.transcript.isEmpty && self.hasMetMinimumDuration {
                        self.resetSilenceTimer(session: currentSession)
                    }

                    if result.isFinal, self.isRecording {
                        // Respect minimum duration even for final results
                        if self.hasMetMinimumDuration {
                            self.invalidateSilenceTimer()
                            self.stopRecording()
                            if !self.transcript.isEmpty {
                                self.onSilenceDetected?()
                            }
                        }
                        return
                    }
                }

                if let error {
                    // Ignore cancellation errors (triggered by our own stopRecording)
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        return // Cancelled — expected
                    }
                    // For other errors, only stop if we've been recording long enough
                    // (transient errors on startup are common and should be ignored)
                    if self.hasMetMinimumDuration {
                        self.stopRecording()
                    }
                    // If still within minimum duration, ignore the error and keep listening
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        invalidateSilenceTimer()

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        recordingStartTime = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Minimum Duration

    /// Whether the current recording has been active long enough for auto-stop.
    private var hasMetMinimumDuration: Bool {
        guard let start = recordingStartTime else { return false }
        return Date().timeIntervalSince(start) >= minimumRecordingDuration
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer(session: UInt) {
        invalidateSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isRecording,
                      self.sessionID == session else { return }
                self.stopRecording()
                if !self.transcript.isEmpty {
                    self.onSilenceDetected?()
                }
            }
        }
    }

    private func invalidateSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
