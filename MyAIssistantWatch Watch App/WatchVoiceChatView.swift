#if os(watchOS)
import SwiftUI
import AVFoundation

struct WatchVoiceChatView: View {
    var connectivity: WatchConnectivityManager
    @State private var isProcessing = false
    @State private var inputText = ""
    @State private var aiResponse = ""
    @State private var errorMessage: String?
    @State private var apiTask: Task<Void, Never>?
    @State private var showingTextInput = false

    private let claudeService = WatchClaudeService()
    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !aiResponse.isEmpty {
                    responseCard
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Thinking...")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                // Voice input button — opens system text input (dictation + scribble + emoji)
                micButton

                // Quick prompts
                if aiResponse.isEmpty && !isProcessing {
                    quickPrompts
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("AI Assistant")
        .sheet(isPresented: $showingTextInput) {
            NavigationStack {
                VStack(spacing: 12) {
                    TextField("Ask anything…", text: $inputText)
                        .font(.body)
                    Button("Send") {
                        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingTextInput = false
                        if !query.isEmpty {
                            sendTextQuery(query)
                        }
                        inputText = ""
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
                .navigationTitle("Ask AI")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
            apiTask?.cancel()
        }
    }

    // MARK: - Response Card (tap to stop TTS)

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text("Assistant")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.accentColor)
            }

            Text(aiResponse)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.1))
        )
        .padding(.horizontal, 4)
        .onTapGesture {
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    // MARK: - Mic Button

    private var micButton: some View {
        Button {
            showingTextInput = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 56, height: 56)

                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel("Ask AI with voice")
    }

    // MARK: - Quick Prompts

    private var quickPrompts: some View {
        VStack(spacing: 6) {
            quickPromptButton("What's next?")
            quickPromptButton("How's my day?")
            quickPromptButton("Prioritize my tasks")
        }
        .padding(.horizontal, 4)
    }

    private func quickPromptButton(_ text: String) -> some View {
        Button {
            sendTextQuery(text)
        } label: {
            Text(text)
                .font(.footnote)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Send to Claude

    private func sendTextQuery(_ text: String) {
        // Re-entrancy guard
        guard !isProcessing else { return }

        synthesizer.stopSpeaking(at: .immediate)
        isProcessing = true
        errorMessage = nil
        aiResponse = ""

        let scheduleContext = buildScheduleContext()

        guard let apiKey = connectivity.apiKey, !apiKey.isEmpty else {
            isProcessing = false
            errorMessage = "No API key. Set it in the iPhone app Settings."
            return
        }

        // Cancel any previous in-flight request
        apiTask?.cancel()

        apiTask = Task {
            do {
                let response = try await claudeService.sendQuery(
                    prompt: text,
                    scheduleContext: scheduleContext,
                    apiKey: apiKey
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    aiResponse = response
                    isProcessing = false
                    speakResponse(response)
                }
            } catch is CancellationError {
                // View dismissed or new query started
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isProcessing = false
                    if (error as? URLError)?.code == .notConnectedToInternet {
                        errorMessage = "No internet connection."
                    } else {
                        errorMessage = (error as? WatchAIError)?.errorDescription ?? "Something went wrong. Try again."
                    }
                }
            }
        }
    }

    private func buildScheduleContext() -> String {
        guard let data = connectivity.scheduleData else { return "" }
        let tasks = data.tasks.map { task in
            let status = task.done ? "done" : "pending"
            let time = task.hasTime ? task.timeString : "no time"
            return "[\(status)] \(task.title) (\(time))"
        }
        var context = "Today's tasks:\n" + tasks.joined(separator: "\n")
        context += "\nCompleted: \(data.completedToday)/\(data.totalToday)"
        context += "\nStreak: \(data.streakDays) days"
        return context
    }

    // MARK: - TTS

    private func speakResponse(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
#endif
