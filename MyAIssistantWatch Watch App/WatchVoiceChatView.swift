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

    // Text input (dictation / keyboard flow)
    @State private var showingTextInput = false
    @State private var textInputValue = ""
    @FocusState private var isInputFocused: Bool

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
                TextField("Speak or type…", text: $textInputValue)
                    .font(.body)
                    .focused($isInputFocused)
                    .onSubmit {
                        submitTextInput()
                    }

                Button {
                    submitTextInput()
                } label: {
                    Text("Send")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(textInputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Auto-focus triggers watchOS system text input (dictation / scribble)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInputFocused = true
                }
            }
        }
    }

    private func submitTextInput() {
        let query = textInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        showingTextInput = false
        isInputFocused = false
        textInputValue = ""
        if !query.isEmpty {
            sendTextQuery(query)
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

    /// Opens the text input sheet with auto-focus so watchOS presents
    /// its system dictation / scribble interface immediately.
    private func startDictation() {
        textInputValue = ""
        showingTextInput = true
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

        // Detect "add task / event / calendar" intent
        if detectsAddIntent(lowerQuery) {
            let (title, parsedDate, hasTime) = extractTaskInfo(from: userQuery)
            if !title.isEmpty {
                let priority = detectPriority(lowerQuery)
                connectivity.addTask(title: title, priority: priority, date: parsedDate, hasTime: hasTime)
                let timeNote = hasTime ? " at \(timeString(parsedDate))" : ""
                actionPerformed = "Added: \(title)\(timeNote)"
                WKInterfaceDevice.current().play(.success)
                return
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

    /// Detects whether the query is an intent to add a task, event, or calendar item.
    private func detectsAddIntent(_ lowerQuery: String) -> Bool {
        let addVerbs = ["add", "create", "schedule", "set up", "put", "remind", "remember", "new", "make"]
        let targetNouns = ["task", "reminder", "todo", "to-do", "to do", "event", "meeting",
                           "appointment", "calendar", "call", "session"]

        let hasVerb = addVerbs.contains { lowerQuery.contains($0) }
        let hasNoun = targetNouns.contains { lowerQuery.contains($0) }

        // "add X" without a noun is also valid: "add call dentist"
        if lowerQuery.hasPrefix("add ") || lowerQuery.hasPrefix("schedule ") ||
           lowerQuery.hasPrefix("remind me ") || lowerQuery.hasPrefix("remember to ") {
            return true
        }

        return hasVerb && hasNoun
    }

    /// Extracts the task title, date (with optional time), and whether a time was specified.
    private func extractTaskInfo(from query: String) -> (title: String, date: Date, hasTime: Bool) {
        let lower = query.lowercased()

        // Strip leading prefixes to isolate the title + time portion
        let prefixes = [
            "add a task to ", "add a task ", "add task ", "add a reminder to ",
            "add a reminder ", "add reminder ", "add a todo ", "add todo ",
            "add a to-do ", "add to-do ", "create a task ", "create task ",
            "create a reminder ", "create an event ", "create event ",
            "schedule a ", "schedule an ", "schedule ",
            "set up a ", "set up an ", "set up ",
            "put ", "make a ", "make an ",
            "remind me to ", "remember to ",
            "add a ", "add an ", "add "
        ]

        var remainder = query
        for prefix in prefixes {
            if lower.hasPrefix(prefix) {
                remainder = String(query.dropFirst(prefix.count))
                break
            }
        }

        remainder = remainder.trimmingCharacters(in: .whitespaces)

        // Strip trailing filler: "on my calendar", "to my calendar", "to my schedule", "to my list"
        let suffixes = [" on my calendar", " to my calendar", " on the calendar",
                        " to my schedule", " on my schedule", " to my list", " on my list"]
        for suffix in suffixes {
            if remainder.lowercased().hasSuffix(suffix) {
                remainder = String(remainder.dropLast(suffix.count))
                break
            }
        }

        // Extract time: "at 3pm", "at 3:30 PM", "at 15:00"
        let (titleWithoutTime, parsedDate, hasTime) = extractTime(from: remainder)

        let title = titleWithoutTime.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return ("", parsedDate, false) }

        let capitalized = title.prefix(1).uppercased() + title.dropFirst()
        return (capitalized, parsedDate, hasTime)
    }

    /// Parses a time expression like "at 3pm" or "at 14:30" from the input.
    /// Returns the cleaned string, the resolved Date, and whether a time was found.
    private func extractTime(from input: String) -> (cleaned: String, date: Date, hasTime: Bool) {
        let today = Calendar.current.startOfDay(for: Date())

        // Match patterns: "at 3pm", "at 3:30pm", "at 3:30 pm", "at 15:00", "at 3 pm"
        let pattern = #"(?i)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|AM|PM)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else {
            return (input, today, false)
        }

        // Extract hour
        guard let hourRange = Range(match.range(at: 1), in: input),
              var hour = Int(input[hourRange]) else {
            return (input, today, false)
        }

        // Extract optional minutes
        var minute = 0
        if let minRange = Range(match.range(at: 2), in: input),
           let m = Int(input[minRange]) {
            minute = m
        }

        // Extract optional am/pm
        if let ampmRange = Range(match.range(at: 3), in: input) {
            let ampm = input[ampmRange].lowercased()
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        } else if hour < 8 {
            // No am/pm specified and hour < 8 → assume PM (e.g., "at 3" = 3 PM)
            hour += 12
        }

        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today

        // Remove the time expression from the string
        let fullMatchRange = Range(match.range, in: input)!
        let cleaned = input.replacingCharacters(in: fullMatchRange, with: "")

        return (cleaned, date, true)
    }

    /// Infers priority from keywords in the query.
    private func detectPriority(_ lowerQuery: String) -> String {
        let highKeywords = ["urgent", "important", "asap", "critical", "high priority"]
        let lowKeywords = ["low priority", "sometime", "whenever", "no rush"]
        if highKeywords.contains(where: { lowerQuery.contains($0) }) { return "High" }
        if lowKeywords.contains(where: { lowerQuery.contains($0) }) { return "Low" }
        return "Medium"
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

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
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
