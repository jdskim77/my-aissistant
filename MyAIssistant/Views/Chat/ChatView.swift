import SwiftUI
import SwiftData
import UserNotifications
import AuthenticationServices

struct ChatView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.usageGateManager) private var usageGateManager
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.chatManager) private var chatManager
    @Environment(\.networkMonitor) private var networkMonitor
    @Environment(\.modelContext) private var modelContext
    @State private var conversationID = "main"
    @State private var inputText = ""
    @State private var isAITyping = false
    @State private var appeared = false
    @State private var errorMessage: String?
    @State private var showingConversations = false
    @AppStorage(AppConstants.voiceModeDefaultKey) private var voiceModeDefault = false
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
    @State private var showReSignIn = false
    @State private var isReSigningIn = false
    @Environment(\.colorScheme) private var colorScheme

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

            // Session expired banner — re-sign-in with Apple
            if showReSignIn {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(AppFonts.bodyMedium(14))
                        Text("Your session has expired.")
                            .font(AppFonts.bodyMedium(13))
                        Spacer()
                        Button {
                            showReSignIn = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .accessibilityLabel("Dismiss")
                    }

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleReSignIn(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .cornerRadius(10)
                    .disabled(isReSigningIn)
                    .opacity(isReSigningIn ? 0.5 : 1)
                }
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppColors.accent.opacity(0.06))
            }

            // Error banner
            if let errorMessage, !showReSignIn {
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
                    .accessibilityLabel("Dismiss error")
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
                    .accessibilityLabel("Dismiss")
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
                TaskBuilderChipsBar(
                    chips: taskBuilder.chips,
                    step: taskBuilder.step,
                    selectedDimensions: taskBuilder.selectedDimensions,
                    onSelect: { chip in
                        handleTaskBuilderChip(chip)
                    },
                    onCancel: {
                        insertLocalMessage(role: .assistant, text: "Task creation cancelled.")
                        taskBuilder.reset()
                    }
                )
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
        // ChatView is presented in a fullScreenCover, which renders in its own
        // scene — the global offline banner pinned at ContentView level does
        // NOT propagate into a cover. Apply it locally so the user always sees
        // ambient connectivity state in the most network-heavy screen.
        .offlineBanner()
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
                .accessibilityLabel("Close chat")
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
            .accessibilityLabel(voiceModeEnabled ? "Turn off voice mode" : "Turn on voice mode")
            .accessibilityHint("Toggles speaking and listening")

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
            .accessibilityLabel("Conversations")
            .accessibilityHint("Switch between or create chat conversations")
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

    // MARK: - Re-Sign-In (Session Expired)

    private func handleReSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = credential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Couldn't read Apple credentials. Please try again."
                return
            }

            let fullName: String? = {
                let parts = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }()

            isReSigningIn = true
            Task {
                do {
                    let backend = ThrivnBackendService(keychain: keychainService)
                    _ = try await backend.signInWithApple(
                        identityToken: identityToken,
                        fullName: fullName,
                        email: credential.email
                    )
                    await MainActor.run {
                        isReSigningIn = false
                        showReSignIn = false
                        errorMessage = nil
                        Haptics.success()
                    }
                } catch {
                    await MainActor.run {
                        isReSigningIn = false
                        errorMessage = "Sign-in failed. Please try again."
                    }
                }
            }

        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = "Sign-in failed. Please try again."
        }
    }

    private func sendMessage(_ text: String) {
        // Intercept: if task builder is waiting for title, capture it instead of sending to AI
        if taskBuilder.step == .title {
            handleTaskBuilderTitleInput(text)
            return
        }

        // Intercept: if task builder is on a chip-based step, try parsing free text
        // before falling through to the AI. Supports typed dates ("friday", "tomorrow")
        // and times ("11:08pm", "9am") so users aren't forced to tap chips.
        if taskBuilder.isActive && taskBuilder.step != .idle {
            insertLocalMessage(role: .user, text: text)

            var handled = false
            if taskBuilder.step == .date {
                handled = taskBuilder.setDateFromText(text)
                // If they typed a time during the date step (e.g. "11:13pm"),
                // assume today and parse the time in one shot.
                if !handled {
                    taskBuilder.selectedDate = Calendar.current.startOfDay(for: Date())
                    if taskBuilder.setTimeFromText(text) {
                        handled = true
                    } else {
                        taskBuilder.selectedDate = nil
                    }
                }
            } else if taskBuilder.step == .time {
                handled = taskBuilder.setTimeFromText(text)
            }

            if handled {
                insertLocalMessage(role: .assistant, text: taskBuilder.promptMessage)
            } else {
                insertLocalMessage(
                    role: .assistant,
                    text: "I didn't catch that. Please tap one of the options below, or tap Cancel to exit.\n\n\(taskBuilder.promptMessage)"
                )
            }
            return
        }

        errorMessage = nil

        // Pre-flight: short-circuit if offline so the user gets an instant
        // explanation instead of waiting up to 60s for URLSession to give up.
        // Critically, do NOT clear inputText — preserve the draft so the user
        // can retry by tapping Send again once they're back online.
        if let monitor = networkMonitor, !monitor.isConnected {
            Haptics.medium()
            errorMessage = "You're offline. Your message is saved — tap Send again when you're back online."
            return
        }

        // Enforce free tier chat limit before delegating (paywall is a UI concern)
        if let gate = usageGateManager, !gate.canSendChat(tier: tier) {
            showChatPaywall = true
            return
        }

        guard let chatManager else {
            errorMessage = "Chat is unavailable."
            return
        }

        inputText = ""
        speechRecognizer.transcript = ""
        isInputFocused = false
        isAITyping = true

        // Keep ChatManager's runtime tier in sync (subscription can change at runtime)
        chatManager.subscriptionTier = tier

        let convoID = conversationID
        Task {
            // ChatManager handles: insert user msg → fetch history → build split prompt
            // (cached stable + uncached volatile) → call provider → parse tags →
            // insert assistant msg → record usage with cache token weighting → persist
            // activity entries → insert error messages on failure.
            let result = await chatManager.sendMessage(text, conversationID: convoID)

            await MainActor.run {
                isAITyping = false

                if result.hasError {
                    if result.errorMessage == "paywall" {
                        showChatPaywall = true
                    } else if result.errorMessage == "sessionExpired" {
                        showReSignIn = true
                    } else {
                        errorMessage = result.errorMessage
                    }
                    return
                }

                // Queue calendar actions for user confirmation (UI concern)
                if !result.calendarActions.isEmpty {
                    let converted = result.calendarActions.map(Self.convert(_:))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        pendingCalendarActions = converted
                    }
                }

                // Speak response aloud if voice mode is on
                if voiceModeEnabled {
                    speechSynthesizer.speak(result.displayText)
                }
            }

            // Schedule alarms async (auth check in scheduleAlarm) — banner only if any succeeded
            if !result.alarms.isEmpty {
                var anyScheduled = false
                for managerAlarm in result.alarms {
                    let alarm = Self.convert(managerAlarm)
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
        }
    }

    // MARK: - SendResult Type Bridges
    //
    // ChatManager defines its own nested CalendarAction / ParsedAlarm types. ChatView
    // has long-standing local types of the same shape used by the pending-actions
    // confirmation UI and scheduleAlarm. Bridge at the boundary to avoid touching
    // either side's internals.

    private static func convert(_ a: ChatManager.CalendarAction) -> CalendarAction {
        switch a {
        case .create(let title, let start, let end, let description, let recurrence, let dimension):
            return .create(title: title, start: start, end: end, description: description, recurrence: recurrence, dimension: dimension)
        case .delete(let eventID):
            return .delete(eventID: eventID)
        }
    }

    private static func convert(_ a: ChatManager.ParsedAlarm) -> ParsedAlarm {
        ParsedAlarm(timeString: a.timeString, label: a.label, repeatsDaily: a.repeatsDaily)
    }

    /// Infer dimension from task title keywords when the AI doesn't provide one.
    private static func inferDimension(from title: String) -> LifeDimension? {
        let lower = title.lowercased()

        let physical = ["walk", "run", "gym", "exercise", "workout", "yoga", "stretch",
                        "sleep", "meal", "cook", "doctor", "dentist", "vitamin", "water",
                        "swim", "hike", "bike", "lift", "pushup", "plank", "jog"]
        let mental = ["read", "study", "learn", "write", "journal", "book", "course",
                      "puzzle", "deep work", "focus", "brainstorm", "plan", "research",
                      "meeting", "standup", "review", "organize"]
        let emotional = ["call", "text", "coffee", "dinner", "lunch", "friend", "family",
                         "date", "therapy", "therapist", "gratitude", "birthday", "catch up",
                         "hang out", "visit", "mom", "dad", "partner"]
        let spiritual = ["volunteer", "donate", "help", "serve", "mentor", "teach",
                         "community", "charity", "give", "church", "temple", "mosque",
                         "meditat", "pray", "kind", "compliment", "listen"]

        if spiritual.contains(where: { lower.contains($0) }) { return .spiritual }
        if emotional.contains(where: { lower.contains($0) }) { return .emotional }
        if physical.contains(where: { lower.contains($0) }) { return .physical }
        if mental.contains(where: { lower.contains($0) }) { return .mental }

        return nil
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
                    case .create(let title, let start, _, _, _, _):
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
        case create(title: String, start: Date, end: Date, description: String?, recurrence: TaskRecurrence, dimension: LifeDimension?)
        case delete(eventID: String)
    }

    private struct ParsedAlarm {
        let timeString: String
        let label: String
        let repeatsDaily: Bool
    }

    private func executeCalendarActions(_ actions: [CalendarAction]) async {
        let syncManager = calendarSyncManager
        let enabledLinks = syncManager?.enabledCalendarLinks() ?? []
        let googleCalendarID = enabledLinks.first(where: { $0.calendarSource == .google })?.calendarID
        let appleCalendarID = enabledLinks.first(where: { $0.calendarSource == .apple })?.calendarID
        let useGoogle = googleCalendarID != nil

        for action in actions {
            switch action {
            case .create(let title, let start, let end, let description, let recurrence, let dimension):
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
                    task.dimension = dimension ?? Self.inferDimension(from: title)
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
