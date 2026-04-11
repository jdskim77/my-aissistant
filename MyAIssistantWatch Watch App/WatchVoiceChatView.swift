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
    @State private var lastFailedQuery: String?

    // Text input (inline — user taps TextField to trigger watchOS dictation picker)
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
        // Sheet removed — input is inline
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

        // Error with retry
        if let error = errorMessage {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                }
                .foregroundColor(.orange)

                if let failedQuery = lastFailedQuery {
                    Button {
                        sendTextQuery(failedQuery)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("Retry")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry last message")
                }
            }
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

    /// Single input: tap the TextField to trigger watchOS input picker (dictation / scribble / keyboard).
    /// This is one tap — no intermediate sheet.
    private var inputControls: some View {
        HStack(spacing: 8) {
            TextField("Speak or type…", text: $textInputValue)
                .font(.body)
                .focused($isInputFocused)
                .onSubmit { submitInlineInput() }

            if !textInputValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    submitInlineInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                // Mic icon hint (decorative — tapping the TextField opens dictation)
                Image(systemName: "mic.fill")
                    .font(.subheadline)
                    .foregroundColor(.accentColor.opacity(0.6))
            }
        }
        .padding(.horizontal, 4)
        .disabled(isProcessing)
    }

    private func submitInlineInput() {
        let query = textInputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        isInputFocused = false
        textInputValue = ""
        if !query.isEmpty {
            sendTextQuery(query)
        }
    }

    // Text input sheet removed — input is now inline in the main view.

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

    // Dictation is now triggered by tapping the inline TextField directly.

    // MARK: - Send to Claude

    private func sendTextQuery(_ text: String) {
        guard !isProcessing else { return }

        synthesizer.stopSpeaking(at: .immediate)
        isProcessing = true
        errorMessage = nil
        actionPerformed = nil
        lastQuery = text
        aiResponse = ""
        lastFailedQuery = nil

        // Execute local actions IMMEDIATELY — don't wait for the API call.
        // This fixes the bug where tasks weren't created if the API key was
        // missing or the network was down.
        parseAndExecuteActions(from: "", userQuery: text)

        // If an action was performed locally, still send to Claude for a
        // conversational response, but don't block the action on it.
        let scheduleContext = buildScheduleContext()

        guard let apiKey = connectivity.apiKey, !apiKey.isEmpty else {
            isProcessing = false
            // If we already performed an action, don't show the API key error
            if actionPerformed == nil {
                errorMessage = "Watch chat needs an Anthropic API key. Open Thrivn on your iPhone → Settings → API Keys."
            }
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
                    speakResponse(response)
                    if actionPerformed == nil {
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            } catch is CancellationError {
                // Dismissed or replaced
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isProcessing = false
                    // If an action was already performed, the core job is done —
                    // just note that the AI response failed silently.
                    if actionPerformed != nil { return }
                    lastFailedQuery = text
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
        let targetNouns = ["task", "reminder", "todo", "to-do", "to do", "event", "meeting",
                           "appointment", "calendar", "call", "session"]

        // Word-boundary verb check to avoid matching "address", "badder", etc.
        let words = Set(lowerQuery.split(separator: " ").map(String.init))
        let addVerbs: Set<String> = ["add", "create", "schedule", "put", "remind", "remember", "new", "make", "book"]
        let hasVerb = !words.isDisjoint(with: addVerbs)
        let hasNoun = targetNouns.contains { lowerQuery.contains($0) }

        // Common natural-language prefix patterns
        let prefixPatterns = [
            "add ", "schedule ", "remind me ", "remember to ",
            "set up ", "create ", "book ", "put ", "make ",
            "can you add", "please add", "i need to add",
            "i want to add", "could you add"
        ]
        if prefixPatterns.contains(where: { lowerQuery.hasPrefix($0) || lowerQuery.contains($0) }) {
            return true
        }

        return hasVerb && hasNoun
    }

    /// Extracts the task title, date (with optional time), and whether a time was specified.
    private func extractTaskInfo(from query: String) -> (title: String, date: Date, hasTime: Bool) {
        let lower = query.lowercased()

        // Strip leading prefixes to isolate the title + time portion
        let prefixes = [
            "can you add ", "please add ", "i need to add ", "i want to add ", "could you add ",
            "add a task to ", "add a task ", "add task ", "add a reminder to ",
            "add a reminder ", "add reminder ", "add a todo ", "add todo ",
            "add a to-do ", "add to-do ", "create a task ", "create task ",
            "create a reminder ", "create an event ", "create event ",
            "schedule a ", "schedule an ", "schedule ",
            "set up a ", "set up an ", "set up ",
            "book a ", "book an ", "book ",
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
