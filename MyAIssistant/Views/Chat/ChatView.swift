import SwiftUI
import SwiftData
import UserNotifications

struct ChatView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(\.chatManager) private var chatManager
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.usageGateManager) private var usageGateManager
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
    @State private var pendingCalendarActions: [ChatManager.CalendarAction] = []
    @FocusState private var isInputFocused: Bool

    private let quickActions = [
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

            // Quick actions
            QuickActionsBar(actions: quickActions) { action in
                sendMessage(action)
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
                    Text("Tap mic to send")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(AppColors.coral.opacity(0.08))
                .onAppear { micPulse = true }
                .onDisappear { micPulse = false }
            }

            HStack(spacing: 10) {
                TextField("Ask your assistant...", text: $inputText, axis: .vertical)
                    .font(AppFonts.body(15))
                    .lineLimit(1...4)
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

                // Microphone button
                Button {
                    handleMicTap()
                } label: {
                    ZStack {
                        // Pulsing ring when recording
                        if speechRecognizer.isRecording {
                            Circle()
                                .stroke(AppColors.coral.opacity(0.3), lineWidth: 3)
                                .frame(width: 52, height: 52)
                                .scaleEffect(micPulse ? 1.2 : 1.0)
                                .opacity(micPulse ? 0.0 : 0.6)
                                .animation(.easeOut(duration: 1.0).repeatForever(autoreverses: false), value: micPulse)
                        }

                        Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(speechRecognizer.isRecording ? .white : AppColors.accent)
                            .frame(width: 44, height: 44)
                            .background(speechRecognizer.isRecording ? AppColors.coral : AppColors.accentLight)
                            .cornerRadius(22)
                    }
                }

                // Send button
                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    sendMessage(text)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textMuted : AppColors.accent)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppColors.surface)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        guard let chatManager else { return }
        errorMessage = nil

        // Check paywall before clearing input so text is preserved if blocked
        if let gate = usageGateManager, !gate.canSendChat(tier: tier) {
            showChatPaywall = true
            return
        }

        inputText = ""
        speechRecognizer.transcript = ""
        isInputFocused = false
        isAITyping = true

        Task {
            let result = await chatManager.sendMessage(text, conversationID: conversationID)

            isAITyping = false

            if result.hasError {
                errorMessage = result.errorMessage
            }

            // Queue calendar actions for user confirmation
            if !result.calendarActions.isEmpty {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pendingCalendarActions = result.calendarActions
                }
            }

            // Speak response aloud if voice mode is on
            if voiceModeEnabled && !result.displayText.isEmpty {
                speechSynthesizer.speak(result.displayText)
            }

            // Schedule alarms async
            if !result.alarms.isEmpty {
                var anyScheduled = false
                for alarm in result.alarms {
                    if await chatManager.scheduleAlarm(alarm) { anyScheduled = true }
                }
                if anyScheduled {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showClockAppPrompt = true
                    }
                }
            }
        }
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
        guard !hasPlayedGreeting, let chatManager else { return }
        hasPlayedGreeting = true

        let greeting = chatManager.insertGreetingMessage(conversationID: conversationID)
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
                    Task {
                        if let chatManager {
                            if let err = await chatManager.executeCalendarActions(actions) {
                                errorMessage = err
                            }
                        }
                    }
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
