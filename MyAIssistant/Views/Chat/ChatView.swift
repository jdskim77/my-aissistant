import SwiftUI
import SwiftData
import UserNotifications

struct ChatView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.usageGateManager) private var usageGateManager
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.modelContext) private var modelContext
    @State private var conversationID = "main"
    @State private var inputText = ""
    @State private var isAITyping = false
    @State private var appeared = false
    @State private var errorMessage: String?
    @State private var showingConversations = false
    @AppStorage(AppConstants.voiceModeDefaultKey) private var voiceModeDefault = true
    @AppStorage(AppConstants.selectedVoiceIDKey) private var selectedVoiceID = ""
    @AppStorage(AppConstants.voiceProviderKey) private var voiceProviderRaw = VoiceProviderType.apple.rawValue
    @State private var speechRecognizer = SpeechRecognizer()
    @State private var speechSynthesizer = SpeechSynthesizer()
    @State private var voiceModeEnabled = false
    @State private var hasPlayedGreeting = false
    @State private var showingMicPermissionAlert = false
    @State private var showClockAppPrompt = false
    @State private var showChatPaywall = false
    @State private var pendingCalendarActions: [CalendarAction] = []
    @FocusState private var isInputFocused: Bool
    @State private var taskBuilder = TaskBuilderState()

    private let quickActions = [
        "Create a Task",
        "What's high priority?",
        "Give me a pep talk",
        "What's due this week?",
        "How am I doing?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Messages — tap to stop AI speech
            ConversationMessages(
                conversationID: conversationID,
                isAITyping: isAITyping
            )
            .onTapGesture {
                if speechSynthesizer.isSpeaking {
                    Haptics.light()
                    speechSynthesizer.stop()
                }
            }

            Divider()
                .background(AppColors.border)

            // Error banner
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                    Text(errorMessage)
                        .font(AppFonts.caption(12))
                    Spacer()
                    Button {
                        self.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(AppColors.coral)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.coral.opacity(0.08))
            }

            // Clock app prompt after alarm is set
            if showClockAppPrompt {
                HStack(spacing: 8) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 14))
                    Text("Notification alarm set.")
                        .font(AppFonts.bodyMedium(13))
                    Spacer()
                    Button {
                        // Open the built-in Clock app's alarm tab
                        if let url = URL(string: "clock-sleep-alarm://") {
                            UIApplication.shared.open(url)
                        }
                        showClockAppPrompt = false
                    } label: {
                        Text("Open Clock App")
                            .font(AppFonts.bodyMedium(12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    Button {
                        showClockAppPrompt = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentLight)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Pending calendar action confirmation
            if !pendingCalendarActions.isEmpty {
                calendarConfirmationBanner
            }

            // Quick actions or Task Builder chips
            if taskBuilder.isActive && !taskBuilder.chips.isEmpty {
                TaskBuilderChipsBar(chips: taskBuilder.chips, onSelect: { chip in
                    handleTaskBuilderChip(chip)
                }, onCancel: {
                    insertLocalMessage(role: .assistant, text: "Task creation cancelled.")
                    taskBuilder.reset()
                })
            } else if !taskBuilder.isActive {
                QuickActionsBar(actions: quickActions) { action in
                    if action == "Create a Task" {
                        taskBuilder.start()
                        insertLocalMessage(role: .assistant, text: taskBuilder.promptMessage)
                    } else {
                        sendMessage(action)
                    }
                }
            }

            // Input bar
            inputBar
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }

            // Initialize voice mode from user preference
            voiceModeEnabled = voiceModeDefault
            speechSynthesizer.selectedVoiceIdentifier = selectedVoiceID.isEmpty ? nil : selectedVoiceID
            speechSynthesizer.selectedProviderType = VoiceProviderType(rawValue: voiceProviderRaw) ?? .apple

            // Wire auto-listen loop: after AI finishes speaking, start recording
            speechSynthesizer.onFinishedSpeaking = {
                guard voiceModeEnabled, !isAITyping else { return }
                startListeningAfterSpeech()
            }

            // Wire silence detection: auto-send transcript after pause
            speechRecognizer.onSilenceDetected = {
                guard voiceModeEnabled else { return }
                autoSendTranscript()
            }

            // Play contextual greeting if voice mode is on
            if voiceModeEnabled {
                playGreeting()
            }
        }
        .onDisappear {
            speechSynthesizer.stop()
            speechRecognizer.stopRecording()
            speechSynthesizer.onFinishedSpeaking = nil
            speechRecognizer.onSilenceDetected = nil
            isMicTransitioning = false
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            if !newValue.isEmpty && speechRecognizer.isRecording {
                inputText = newValue
            }
        }
        .onChange(of: speechSynthesizer.isSpeaking) { _, isSpeaking in
            // Hard guard: mic must never be on while AI is talking
            if isSpeaking && speechRecognizer.isRecording {
                speechRecognizer.stopRecording()
            }
        }
        .alert("Microphone Access Required", isPresented: $showingMicPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable microphone and speech recognition access in Settings to use voice input.")
        }
        .sheet(isPresented: $showingConversations) {
            ConversationListView(selectedConversationID: $conversationID)
        }
        .sheet(isPresented: $showChatPaywall) {
            NavigationStack {
                VStack(spacing: 24) {
                    PaywallCard(
                        title: "Chat limit reached",
                        message: "You've used all \(AppConstants.freeChatMessagesPerMonth) free messages this month. Upgrade to Pro for unlimited AI chat."
                    ) {
                        showChatPaywall = false
                        // Navigate to subscription view
                    }

                    if let gate = usageGateManager {
                        Text("Next reset: start of next month")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    }

                    Button {
                        showChatPaywall = false
                    } label: {
                        Text("Close")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(24)
                .navigationTitle("Upgrade")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            if let onDismiss {
                Button {
                    speechSynthesizer.stop()
                    speechRecognizer.stopRecording()
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                        .padding(8)
                        .background(AppColors.surface)
                        .cornerRadius(8)
                }
            }

            AIActivityOrb(
                isActive: isAITyping || speechSynthesizer.isSpeaking,
                size: 38
            )
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI Assistant")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                Text(providerLabel)
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }

            Spacer()

            Button {
                voiceModeEnabled.toggle()
                if !voiceModeEnabled {
                    speechSynthesizer.stop()
                    speechRecognizer.stopRecording()
                } else if !hasPlayedGreeting {
                    playGreeting()
                } else if !speechSynthesizer.isSpeaking && !isAITyping {
                    startListeningAfterSpeech()
                }
            } label: {
                Image(systemName: voiceModeEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(voiceModeEnabled ? AppColors.accent : AppColors.textMuted)
                    .padding(8)
                    .background(voiceModeEnabled ? AppColors.accentLight : AppColors.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(voiceModeEnabled ? AppColors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }

            Button {
                showingConversations = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.accent)
                    .padding(8)
                    .background(AppColors.accentLight)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(AppColors.surface)
    }

    private var providerLabel: String {
        switch tier {
        case .powerUser:
            if keychainService.openAIAPIKey() != nil {
                return "Powered by OpenAI"
            }
            return "Powered by Claude"
        default:
            return "Powered by Claude"
        }
    }

    // MARK: - Input bar

    @State private var micPulse = false

    /// Context-aware button state — depends on text presence + recording state.
    private var hasText: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Note: actionButtonIcon was removed — the button now uses a SwiftUI
    // ThrivnCompassMark for idle/recording states and an SF Symbol arrow
    // only for the send state. Branching happens inline in the button label.

    private var actionButtonColor: Color {
        // Coral signals "actively recording"; accent for everything else
        speechRecognizer.isRecording ? AppColors.coral : AppColors.accent
    }

    private var actionButtonAccessibilityLabel: String {
        if speechRecognizer.isRecording { return "Stop recording" }
        if hasText { return "Send message" }
        return "Start voice input"
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Free tier remaining messages indicator
            if tier == .free, let gate = usageGateManager {
                let remaining = gate.remainingChatMessages
                if remaining <= 5 {
                    HStack(spacing: 6) {
                        Image(systemName: remaining == 0 ? "exclamationmark.circle.fill" : "info.circle.fill")
                            .font(.system(size: 12))
                        Text(remaining == 0
                            ? "No messages remaining this month"
                            : "\(remaining) message\(remaining == 1 ? "" : "s") remaining this month")
                            .font(AppFonts.caption(11))
                    }
                    .foregroundColor(remaining <= 2 ? AppColors.coral : AppColors.textMuted)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(remaining <= 2 ? AppColors.coral.opacity(0.06) : AppColors.surface.opacity(0.5))
                }
            }

            // Recording indicator banner
            if speechRecognizer.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppColors.coral)
                        .frame(width: 8, height: 8)
                        .scaleEffect(micPulse ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: micPulse)
                    Text("Listening...")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.coral)
                    Spacer()
                    Button {
                        // Cancel recording without sending
                        speechRecognizer.stopRecording()
                        inputText = ""
                        speechRecognizer.transcript = ""
                    } label: {
                        Text("Cancel")
                            .font(AppFonts.caption(11).weight(.medium))
                            .foregroundColor(AppColors.coral)
                    }
                    .accessibilityLabel("Cancel recording")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(AppColors.coral.opacity(0.08))
                .onAppear { micPulse = true }
                .onDisappear { micPulse = false }
            }

            // Single context-aware button: mic when empty, send when text present.
            // TextField auto-grows up to 5 lines so dictated text is fully visible.
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Tap mic to speak or type...", text: $inputText, axis: .vertical)
                    .font(AppFonts.body(15))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.surface)
                    .cornerRadius(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(
                                speechRecognizer.isRecording ? AppColors.coral : AppColors.border,
                                lineWidth: speechRecognizer.isRecording ? 2.5 : 1
                            )
                    )

                // Single context-aware action button.
                // States:
                //   - Recording (regardless of text): tap stops recording and auto-sends
                //     if there's text (handleMicTap already does this)
                //   - Has text, not recording: send the message
                //   - Empty, not recording: start dictation
                Button {
                    if speechRecognizer.isRecording {
                        // handleMicTap will stop recording AND send if there's text.
                        // Do NOT call sendMessage again — that would double-send.
                        handleMicTap()
                    } else {
                        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            handleMicTap() // Start dictation
                        } else {
                            sendMessage(trimmed)
                        }
                    }
                } label: {
                    ZStack {
                        // Outer pulsing ring when recording (kept for accent, in addition to compass orbit)
                        if speechRecognizer.isRecording {
                            Circle()
                                .stroke(AppColors.coral.opacity(0.3), lineWidth: 3)
                                .frame(width: 52, height: 52)
                                .scaleEffect(micPulse ? 1.2 : 1.0)
                                .opacity(micPulse ? 0.0 : 0.6)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: micPulse)
                        }

                        // Filled circular background — coral when recording, accent otherwise
                        Circle()
                            .fill(actionButtonColor)
                            .frame(width: 44, height: 44)

                        // Foreground glyph: compass mark for idle/recording, arrow for send
                        if hasText && !speechRecognizer.isRecording {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            ThrivnCompassMark(
                                color: .white,
                                size: 33,
                                isAnimating: speechRecognizer.isRecording
                            )
                        }
                    }
                }
                .accessibilityLabel(actionButtonAccessibilityLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppColors.surface)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        // Intercept: if task builder is waiting for title, capture it instead of sending to AI
        if taskBuilder.step == .title {
            handleTaskBuilderTitleInput(text)
            return
        }

        errorMessage = nil

        // Enforce free tier chat limit
        if let gate = usageGateManager, !gate.canSendChat(tier: tier) {
            showChatPaywall = true
            return
        }

        // Fetch prior history BEFORE inserting the new message to avoid duplicate
        let convoID = conversationID
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationID == convoID },
            sortBy: [SortDescriptor(\ChatMessage.timestamp)]
        )
        let priorHistory = (try? modelContext.fetch(descriptor)) ?? []

        let userMessage = ChatMessage(role: .user, content: text, conversationID: conversationID)
        modelContext.insert(userMessage)
        modelContext.safeSave()
        inputText = ""
        speechRecognizer.transcript = ""
        isInputFocused = false
        isAITyping = true

        Task {
            do {
                let provider = try AIProviderFactory.provider(
                    for: tier,
                    useCase: .chat,
                    keychain: keychainService
                )

                let enabledLinks = calendarSyncManager?.enabledCalendarLinks() ?? []
                let hasGoogle = enabledLinks.contains { $0.calendarSource == .google }
                let hasApple = enabledLinks.contains { $0.calendarSource == .apple }
                    || calendarSyncManager?.appleCalendarAuthorized == true

                let systemPrompt = AIPromptBuilder.chatSystemPrompt(
                    scheduleSummary: taskManager?.scheduleSummary() ?? "",
                    completionRate: patternEngine?.completionRate() ?? 0,
                    streak: patternEngine?.currentStreak() ?? 0,
                    hasGoogleCalendar: hasGoogle,
                    hasAppleCalendar: hasApple,
                    activitySummary: patternEngine?.activitySummaryText() ?? "",
                    patternInsights: patternEngine?.patternInsightsText() ?? ""
                )

                let aiResponse = try await provider.sendMessage(
                    userMessage: text,
                    conversationHistory: Array(priorHistory.suffix(10)),
                    systemPrompt: systemPrompt
                )

                let parsed = parseResponseTags(from: aiResponse.content)

                await MainActor.run {
                    isAITyping = false

                    let assistantMessage = ChatMessage(role: .assistant, content: parsed.displayText, conversationID: conversationID)
                    modelContext.insert(assistantMessage)

                    // Track usage
                    usageGateManager?.recordChatMessage(inputTokens: aiResponse.inputTokens, outputTokens: aiResponse.outputTokens)

                    // Queue calendar actions for user confirmation
                    if !parsed.calendarActions.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            pendingCalendarActions = parsed.calendarActions
                        }
                    }

                    // Store tracked activities
                    for activity in parsed.activities {
                        let entry = ActivityEntry(
                            activity: activity.description,
                            category: activity.category
                        )
                        modelContext.insert(entry)
                    }

                    // Speak response aloud if voice mode is on
                    if voiceModeEnabled {
                        speechSynthesizer.speak(parsed.displayText)
                    }

                    modelContext.safeSave()
                }

                // Schedule alarms async (requires auth check) — only show banner if at least one succeeded
                if !parsed.alarms.isEmpty {
                    var anyScheduled = false
                    for alarm in parsed.alarms {
                        if await scheduleAlarm(alarm) { anyScheduled = true }
                    }
                    if anyScheduled {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showClockAppPrompt = true
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isAITyping = false
                    if let aiError = error as? AIError, case .noAPIKey = aiError {
                        errorMessage = "No API key set. Add one in Settings."
                        let msg = ChatMessage(
                            role: .assistant,
                            content: "I need an API key to work. Please add your Anthropic API key in Settings to get started!",
                            conversationID: conversationID
                        )
                        modelContext.insert(msg)
                    } else if let aiError = error as? AIError, case .rateLimited = aiError {
                        errorMessage = "Too many requests — please wait a moment."
                        let msg = ChatMessage(
                            role: .assistant,
                            content: "I'm getting a lot of requests right now. Give me a moment and try again!",
                            conversationID: conversationID
                        )
                        modelContext.insert(msg)
                    } else {
                        errorMessage = "Connection issue — please try again."
                        let msg = ChatMessage(
                            role: .assistant,
                            content: "I'm having trouble connecting right now. Please check your internet connection and try again.",
                            conversationID: conversationID
                        )
                        modelContext.insert(msg)
                    }
                    modelContext.safeSave()
                }
            }
        }
    }

    // MARK: - Task Builder Helpers

    private func handleTaskBuilderTitleInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insertLocalMessage(role: .user, text: trimmed)
        taskBuilder.setTitle(trimmed)
        insertLocalMessage(role: .assistant, text: taskBuilder.promptMessage)
        inputText = ""
        speechRecognizer.transcript = ""
        isInputFocused = false
    }

    private func handleTaskBuilderChip(_ chip: TaskBuilderChip) {
        // Echo user selection as a message
        let displayText = [chip.icon, chip.label].compactMap { $0 }.joined(separator: " ")
        insertLocalMessage(role: .user, text: displayText)

        if taskBuilder.step == .confirm && chip.value == "create" {
            let task = taskBuilder.buildTask()
            taskManager?.addTask(task)
            insertLocalMessage(role: .assistant, text: "✅ Task created: \"\(task.title)\"")
            Haptics.success()
            taskBuilder.reset()
            return
        }

        if taskBuilder.step == .confirm && chip.value == "cancel" {
            insertLocalMessage(role: .assistant, text: "Task creation cancelled.")
            taskBuilder.reset()
            return
        }

        taskBuilder.selectChip(chip)

        // Show next prompt
        if taskBuilder.isActive {
            insertLocalMessage(role: .assistant, text: taskBuilder.promptMessage)
        }
    }

    private func insertLocalMessage(role: MessageRole, text: String) {
        let msg = ChatMessage(role: role, content: text, conversationID: conversationID)
        modelContext.insert(msg)
        modelContext.safeSave()
    }

    @State private var isMicTransitioning = false

    private func handleMicTap() {
        // Prevent double-tap race condition
        guard !isMicTransitioning else { return }

        let wasSpeaking = speechSynthesizer.isSpeaking
        speechSynthesizer.stop()

        if speechRecognizer.isRecording {
            speechRecognizer.stopRecording()
            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sendMessage(text)
            }
        } else {
            isMicTransitioning = true
            Task {
                // Wait for audio session to fully tear down after stopping TTS
                if wasSpeaking {
                    try? await Task.sleep(for: .milliseconds(700))
                }
                await speechRecognizer.requestPermission()
                if speechRecognizer.permissionGranted {
                    try? speechRecognizer.startRecording()
                } else {
                    showingMicPermissionAlert = true
                }
                isMicTransitioning = false
            }
        }
    }

    // MARK: - Voice Conversation Loop

    private func playGreeting() {
        guard !hasPlayedGreeting else { return }
        hasPlayedGreeting = true

        let todayTasks = taskManager?.todayTasks() ?? []
        let highPriority = taskManager?.highPriorityUpcoming(limit: 1) ?? []

        // Load previously used openers today to avoid repeats
        let usedOpeners = GreetingManager.loadUsedOpenersForToday()

        let result = VariedGreetingBuilder.greetingWithOpener(
            todayTaskCount: todayTasks.count,
            completedTodayCount: todayTasks.filter(\.done).count,
            highPriorityTitles: highPriority.map(\.title),
            completionRate: patternEngine?.completionRate() ?? 0,
            streak: patternEngine?.currentStreak() ?? 0,
            excludeOpeners: usedOpeners
        )
        let greeting = result.text

        // Track the opener so it won't repeat today
        GreetingManager.recordUsedOpenerForToday(result.opener)

        let greetingMessage = ChatMessage(
            role: .assistant,
            content: greeting,
            conversationID: conversationID
        )
        modelContext.insert(greetingMessage)
        modelContext.safeSave()

        speechSynthesizer.speak(greeting)
    }

    private func startListeningAfterSpeech() {
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard voiceModeEnabled,
                  !speechSynthesizer.isSpeaking,
                  !speechRecognizer.isRecording,
                  !isAITyping,
                  !isMicTransitioning else { return }
            await speechRecognizer.requestPermission()
            guard !speechSynthesizer.isSpeaking,
                  !speechRecognizer.isRecording else { return }
            if speechRecognizer.permissionGranted {
                try? speechRecognizer.startRecording()
            }
        }
    }

    private func autoSendTranscript() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            inputText = ""
            if voiceModeEnabled {
                startListeningAfterSpeech()
            }
            return
        }
        sendMessage(text)
    }

    // MARK: - Calendar Confirmation Banner

    private var calendarConfirmationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                Text("Calendar changes requested")
                    .font(AppFonts.bodyMedium(13))
                Spacer()
            }
            .foregroundColor(AppColors.accent)

            ForEach(Array(pendingCalendarActions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 6) {
                    switch action {
                    case .create(let title, let start, _, _, _):
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(AppColors.completionGreen)
                            .font(.system(size: 12))
                        Text("Create: \(title)")
                            .font(AppFonts.body(12))
                        Text("(\(start.formatted(as: "MMM d, h:mm a")))")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    case .delete(let eventID):
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(AppColors.coral)
                            .font(.system(size: 12))
                        Text("Delete event: \(eventID)")
                            .font(AppFonts.body(12))
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pendingCalendarActions = []
                    }
                } label: {
                    Text("Dismiss")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                }

                Button {
                    let actions = pendingCalendarActions
                    withAnimation(.easeInOut(duration: 0.2)) {
                        pendingCalendarActions = []
                    }
                    Task { await executeCalendarActions(actions) }
                } label: {
                    Text("Approve")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.accent)
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.accentLight)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Calendar Action Parsing

    private enum CalendarAction {
        case create(title: String, start: Date, end: Date, description: String?, recurrence: TaskRecurrence)
        case delete(eventID: String)
    }

    private struct ParsedAlarm {
        let timeString: String
        let label: String
        let repeatsDaily: Bool
    }

    private struct ParsedResponse {
        let displayText: String
        let calendarActions: [CalendarAction]
        let activities: [(category: String, description: String)]
        let alarms: [ParsedAlarm]
    }

    private func parseResponseTags(from text: String) -> ParsedResponse {
        var displayText = text
        var calendarActions: [CalendarAction] = []
        var activities: [(category: String, description: String)] = []
        var alarms: [ParsedAlarm] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        // Parse CREATE_EVENT tags: [[CREATE_EVENT:title|start|end|desc]] or [[CREATE_EVENT:title|start|end|desc|recurrence]]
        let createPattern = /\[\[CREATE_EVENT:(.+?)\|(.+?)\|(.+?)\|(.*?)(?:\|(daily|weekly|biweekly|monthly))?\]\]/
        for match in text.matches(of: createPattern) {
            let title = String(match.1).trimmingCharacters(in: .whitespaces)
            let startStr = String(match.2).trimmingCharacters(in: .whitespaces)
            let endStr = String(match.3).trimmingCharacters(in: .whitespaces)
            let desc = String(match.4).trimmingCharacters(in: .whitespaces)
            let recStr = match.5.map { String($0).lowercased() }
            let recurrence = recStr.flatMap { TaskRecurrence(rawValue: $0.capitalized) } ?? .none

            if let startDate = dateFormatter.date(from: startStr),
               let endDate = dateFormatter.date(from: endStr) {
                calendarActions.append(.create(
                    title: title,
                    start: startDate,
                    end: endDate,
                    description: desc.isEmpty ? nil : desc,
                    recurrence: recurrence
                ))
            }
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse DELETE_EVENT tags
        let deletePattern = /\[\[DELETE_EVENT:(.+?)\]\]/
        for match in text.matches(of: deletePattern) {
            let eventID = String(match.1).trimmingCharacters(in: .whitespaces)
            calendarActions.append(.delete(eventID: eventID))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse ACTIVITY tags
        let activityPattern = /\[\[ACTIVITY:(.+?)\|(.+?)\]\]/
        for match in text.matches(of: activityPattern) {
            let category = String(match.1).trimmingCharacters(in: .whitespaces)
            let description = String(match.2).trimmingCharacters(in: .whitespaces)
            activities.append((category: category, description: description))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        // Parse SET_ALARM tags: [[SET_ALARM:HH:mm|Label]] or [[SET_ALARM:HH:mm|Label|daily]]
        let alarmPattern = /\[\[SET_ALARM:(.+?)\|(.+?)(?:\|(daily))?\]\]/
        for match in text.matches(of: alarmPattern) {
            let timeStr = String(match.1).trimmingCharacters(in: .whitespaces)
            let label = String(match.2).trimmingCharacters(in: .whitespaces)
            let repeats = match.3 != nil
            alarms.append(ParsedAlarm(timeString: timeStr, label: label, repeatsDaily: repeats))
            displayText = displayText.replacingOccurrences(of: String(match.0), with: "")
        }

        return ParsedResponse(
            displayText: displayText.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarActions: calendarActions,
            activities: activities,
            alarms: alarms
        )
    }

    private func executeCalendarActions(_ actions: [CalendarAction]) async {
        let syncManager = calendarSyncManager
        let enabledLinks = syncManager?.enabledCalendarLinks() ?? []
        let googleCalendarID = enabledLinks.first(where: { $0.calendarSource == .google })?.calendarID
        let appleCalendarID = enabledLinks.first(where: { $0.calendarSource == .apple })?.calendarID
        let useGoogle = googleCalendarID != nil

        for action in actions {
            switch action {
            case .create(let title, let start, let end, let description, let recurrence):
                // Dedup FIRST: check if a task with the same title exists on this day
                let isDuplicate = await MainActor.run {
                    let calendar = Calendar.current
                    let dayStart = calendar.startOfDay(for: start)
                    let dayEnd = calendar.safeDate(byAdding: .day, value: 1, to: dayStart)
                    let titleLower = title.lowercased()
                    let descriptor = FetchDescriptor<TaskItem>(
                        predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
                    )
                    let existing = (try? modelContext.fetch(descriptor)) ?? []
                    return existing.contains { $0.title.lowercased() == titleLower }
                }
                guard !isDuplicate else { continue }

                // Create calendar event, then local task
                var calendarID: String?

                if let syncManager {
                    do {
                        if useGoogle, let calID = googleCalendarID {
                            let eventID = try await syncManager.googleService.createEvent(
                                calendarID: calID,
                                title: title,
                                startDate: start,
                                endDate: end,
                                description: description
                            )
                            calendarID = "google:\(eventID)"
                        } else if appleCalendarID != nil || syncManager.appleCalendarAuthorized {
                            let eventID = try await syncManager.eventKitService.createEvent(
                                title: title,
                                startDate: start,
                                endDate: end,
                                notes: description,
                                calendarID: appleCalendarID
                            )
                            calendarID = eventID
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Calendar sync failed, but task was added: \(error.localizedDescription)"
                        }
                    }
                }

                await MainActor.run {
                    let task = TaskItem(
                        title: title,
                        category: .personal,
                        priority: .medium,
                        date: start,
                        icon: calendarID?.hasPrefix("google:") == true ? "🌐" : "📅",
                        notes: description ?? "",
                        recurrence: recurrence
                    )
                    task.externalCalendarID = calendarID
                    modelContext.insert(task)
                    modelContext.safeSave()
                }

            case .delete(let eventID):
                // Try to delete from calendar, then always remove the task
                if let syncManager {
                    do {
                        if eventID.hasPrefix("google:") {
                            let googleEventID = String(eventID.dropFirst("google:".count))
                            if let calID = googleCalendarID {
                                try await syncManager.googleService.deleteEvent(
                                    calendarID: calID,
                                    eventID: googleEventID
                                )
                            }
                        } else {
                            try await syncManager.eventKitService.deleteEvent(identifier: eventID)
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Failed to delete calendar event: \(error.localizedDescription)"
                        }
                    }
                }

                await MainActor.run {
                    let targetID = eventID
                    let descriptor = FetchDescriptor<TaskItem>(
                        predicate: #Predicate { $0.externalCalendarID == targetID }
                    )
                    if let tasks = try? modelContext.fetch(descriptor) {
                        for task in tasks {
                            modelContext.delete(task)
                        }
                        modelContext.safeSave()
                    }
                }
            }
        }
    }

    // MARK: - Alarm Scheduling

    /// Returns true if the alarm was successfully scheduled.
    @discardableResult
    private func scheduleAlarm(_ alarm: ParsedAlarm) async -> Bool {
        // Bug fix #5: check notification auth before scheduling
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            errorMessage = "Notifications are disabled. Enable them in Settings to receive alarms."
            return false
        }

        // Bug fix #4: try multiple time formats to handle "7:00" as well as "07:00"
        let formats = ["HH:mm", "H:mm", "h:mm a", "h:mma", "h:mm"]
        var parsedTime: Date?
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            if let d = f.date(from: alarm.timeString) { parsedTime = d; break }
        }
        guard let parsedTime else {
            errorMessage = "Couldn't parse alarm time \"\(alarm.timeString)\". Please try again."
            return false
        }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: parsedTime)
        let minute = calendar.component(.minute, from: parsedTime)

        // Build the target date: today if still in the future, otherwise tomorrow
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let alarmDate: Date
        if let candidate = calendar.date(from: components), candidate > now {
            alarmDate = candidate
        } else {
            alarmDate = calendar.date(from: components).flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0)
            } ?? now
        }

        let entry = AlarmEntry(
            label: alarm.label,
            time: alarmDate,
            repeatsDaily: alarm.repeatsDaily
        )
        modelContext.insert(entry)

        let notificationManager = NotificationManager()
        notificationManager.scheduleAlarm(
            notificationID: entry.notificationID,
            label: alarm.label,
            time: alarmDate,
            repeatsDaily: alarm.repeatsDaily
        )
        return true
    }
}

// MARK: - Conversation Messages (inner view with @Query)

private struct ConversationMessages: View {
    let conversationID: String
    let isAITyping: Bool

    @Query private var messages: [ChatMessage]

    init(conversationID: String, isAITyping: Bool) {
        self.conversationID = conversationID
        self.isAITyping = isAITyping
        let convoID = conversationID
        self._messages = Query(
            filter: #Predicate<ChatMessage> { $0.conversationID == convoID },
            sort: \ChatMessage.timestamp
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    }

                    ForEach(messages, id: \.id) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isAITyping {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isAITyping) { _, typing in
                if typing {
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Text("✦")
                .font(.system(size: 40))
                .foregroundColor(AppColors.accent)

            Text("How can I help?")
                .font(AppFonts.heading(20))
                .foregroundColor(AppColors.textPrimary)

            Text("I know your schedule, patterns, and goals.\nAsk me anything!")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var typingIndicator: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppColors.textMuted)
                        .frame(width: 7, height: 7)
                        .opacity(0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                            value: isAITyping
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(AppColors.surface)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
            )

            Spacer()
        }
    }
}
