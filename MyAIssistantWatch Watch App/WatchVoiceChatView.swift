#if os(watchOS)
import SwiftUI
import AVFoundation
import WatchKit

struct WatchVoiceChatView: View {
    var connectivity: WatchConnectivityManager
    @State private var isProcessing = false
    @State private var lastQuery = ""
    @State private var aiResponse = ""
    @State private var errorMessage: String?
    @State private var apiTask: Task<Void, Never>?
    @State private var actionPerformed: String?
    @State private var micPulse = false

    // Text input (keyboard flow)
    @State private var showingTextInput = false
    @State private var textInputValue = ""

    private let claudeService = WatchClaudeService()
    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                conversationArea

                if isProcessing {
                    processingIndicator
                }

                inputControls
                    .padding(.top, 4)

                if aiResponse.isEmpty && !isProcessing && lastQuery.isEmpty {
                    quickPrompts
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("AI Assistant")
        .sheet(isPresented: $showingTextInput) {
            textInputSheet
        }
        .onDisappear {
            synthesizer.stopSpeaking(at: .immediate)
            apiTask?.cancel()
        }
    }

    // MARK: - Conversation Area

    @ViewBuilder
    private var conversationArea: some View {
        // User's query bubble (right-aligned)
        if !lastQuery.isEmpty {
            HStack {
                Spacer()
                Text(lastQuery)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.2))
                    )
            }
            .padding(.horizontal, 4)
        }

        // AI response bubble (left-aligned)
        if !aiResponse.isEmpty {
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

        // Action confirmation
        if let action = actionPerformed {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(action)
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.12))
            )
            .padding(.horizontal, 4)
        }

        // Error
        if let error = errorMessage {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text(error)
                    .font(.caption2)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.08))
            )
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.accentColor)
            Text("Thinking...")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Input Controls

    /// Two distinct input modes: voice (primary) and keyboard (secondary)
    private var inputControls: some View {
        VStack(spacing: 8) {
            // Primary: Voice dictation button
            Button {
                guard !isProcessing else { return }
                WKInterfaceDevice.current().play(.click)
                startDictation()
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        // Pulse ring
                        if !isProcessing {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 40, height: 40)
                                .scaleEffect(micPulse ? 1.2 : 1.0)
                                .opacity(micPulse ? 0 : 0.5)
                                .animation(
                                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                                    value: micPulse
                                )
                        }

                        Circle()
                            .fill(isProcessing ? Color.gray : Color.accentColor)
                            .frame(width: 36, height: 36)

                        Image(systemName: "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Tap to speak")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        Text("Dictation opens immediately")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.horizontal, 4)

            // Secondary: Keyboard text input
            Button {
                guard !isProcessing else { return }
                showingTextInput = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.caption2)
                    Text("Type instead")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
        .onAppear { micPulse = true }
    }

    // MARK: - Text Input Sheet (keyboard flow)

    private var textInputSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Type your question…", text: $textInputValue)
                    .font(.body)

                Button {
                    let query = textInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    showingTextInput = false
                    textInputValue = ""
                    if !query.isEmpty {
                        sendTextQuery(query)
                    }
                } label: {
                    Text("Send")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(textInputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Type")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Quick Prompts

    private var quickPrompts: some View {
        VStack(spacing: 6) {
            Text("Try saying")
                .font(.caption2)
                .foregroundColor(.secondary)

            quickPromptButton("What's next?", icon: "arrow.right.circle")
            quickPromptButton("Add task call dentist", icon: "plus.circle")
            quickPromptButton("How's my day?", icon: "chart.bar")
        }
        .padding(.horizontal, 4)
    }

    private func quickPromptButton(_ text: String, icon: String) -> some View {
        Button {
            sendTextQuery(text)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(text)
                    .font(.footnote)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Dictation

    /// Opens watchOS system dictation directly via WKExtension.
    /// Falls back to text input sheet if unavailable.
    private func startDictation() {
        // On watchOS, presentTextInputController shows dictation as the primary option
        // In SwiftUI lifecycle apps, we access it through WKExtension
        if let controller = WKExtension.shared().visibleInterfaceController {
            controller.presentTextInputController(
                withSuggestions: ["What's next?", "Add a task", "How's my day?"],
                allowedInputMode: .allowAnimatedEmoji
            ) { results in
                guard let text = results?.first as? String else { return }
                let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    DispatchQueue.main.async {
                        self.sendTextQuery(query)
                    }
                }
            }
        } else {
            // Fallback: SwiftUI lifecycle — use text input sheet
            // watchOS TextField opens dictation when tapped in the sheet
            showingTextInput = true
        }
    }

    // MARK: - Send to Claude

    private func sendTextQuery(_ text: String) {
        guard !isProcessing else { return }

        synthesizer.stopSpeaking(at: .immediate)
        isProcessing = true
        errorMessage = nil
        actionPerformed = nil
        lastQuery = text
        aiResponse = ""

        let scheduleContext = buildScheduleContext()

        guard let apiKey = connectivity.apiKey, !apiKey.isEmpty else {
            isProcessing = false
            errorMessage = "No API key. Set it in the iPhone app Settings."
            return
        }

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
                    parseAndExecuteActions(from: response, userQuery: text)
                    speakResponse(response)
                    WKInterfaceDevice.current().play(.success)
                }
            } catch is CancellationError {
                // Dismissed or replaced
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isProcessing = false
                    WKInterfaceDevice.current().play(.failure)
                    if (error as? URLError)?.code == .notConnectedToInternet {
                        errorMessage = "No internet connection."
                    } else {
                        errorMessage = (error as? WatchAIError)?.errorDescription ?? "Something went wrong. Try again."
                    }
                }
            }
        }
    }

    // MARK: - Action Parsing

    private func parseAndExecuteActions(from response: String, userQuery: String) {
        let lowerQuery = userQuery.lowercased()

        // Detect "add task" intent
        if lowerQuery.contains("add") && (lowerQuery.contains("task") || lowerQuery.contains("reminder") || lowerQuery.contains("todo")) {
            let taskTitle = extractTaskTitle(from: userQuery)
            if !taskTitle.isEmpty {
                let date = Calendar.current.startOfDay(for: Date())
                connectivity.addTask(title: taskTitle, priority: "Medium", date: date, hasTime: false)
                actionPerformed = "Added: \(taskTitle)"
                WKInterfaceDevice.current().play(.success)
            }
        }

        // Detect task completion intent
        if lowerQuery.contains("complete") || lowerQuery.contains("done") || lowerQuery.contains("finish") || lowerQuery.contains("mark") {
            if let task = findTaskInQuery(lowerQuery) {
                connectivity.toggleTaskCompletion(task.id)
                actionPerformed = "Completed: \(task.title)"
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func extractTaskTitle(from query: String) -> String {
        let lower = query.lowercased()
        let prefixes = [
            "add a task ", "add task ", "add a reminder ", "add reminder ",
            "add a todo ", "add todo ", "create task ", "create a task ",
            "remind me to ", "remember to "
        ]
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                let title = String(query.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title.prefix(1).uppercased() + title.dropFirst()
                }
            }
        }
        return ""
    }

    private func findTaskInQuery(_ query: String) -> WatchScheduleData.WatchTask? {
        for task in connectivity.activeTasks {
            let titleWords = task.title.lowercased().split(separator: " ")
            let matchCount = titleWords.filter { query.contains($0) }.count
            if matchCount >= 1 && Double(matchCount) / Double(titleWords.count) >= 0.5 {
                return task
            }
        }
        return nil
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
