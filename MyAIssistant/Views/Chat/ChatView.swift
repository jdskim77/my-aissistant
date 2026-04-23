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
    @Environment(\.nudgeEngine) private var nudgeEngine

    /// Delivered-but-unreacted nudges sorted most-recent first. The
    /// Coach tab pins the single most-recent one above the transcript
    /// so the user's reaction is one tap away. Filter is in-memory
    /// rather than a #Predicate to dodge the same Swift type-check
    /// timeout that bit CoachSettingsView — the row count is tiny.
    @Query(sort: [SortDescriptor(\Nudge.createdAt, order: .reverse)])
    private var allRecentNudges: [Nudge]

    private var pinnedNudge: Nudge? {
        // Plain-closure filter (not #Predicate) so we can reference the
        // enum's raw value directly — catches enum renames at compile
        // time. Fix for BUG-03.
        let deliveredRaw = NudgeStatus.delivered.rawValue
        return allRecentNudges.first { $0.statusRaw == deliveredRaw && $0.userResponseRaw == nil }
    }

    /// Records a reaction on a nudge, with a fallback direct-write to
    /// the model context if the NudgeEngine environment isn't wired.
    /// Without this fallback, tapping 👍/👎 silently did nothing when
    /// `nudgeEngine` was nil (BUG-04): the @Query filter would stay
    /// matched, the card would stay pinned, and no hit-rate signal
    /// would be captured — corrupting dogfood data. Fallback mirrors
    /// NudgeEngine.recordResponse so the behavior stays consistent.
    private func recordNudgeResponse(nudge: Nudge, response: UserNudgeResponse) {
        if let engine = nudgeEngine {
            engine.recordResponse(nudgeID: nudge.id, response: response)
            return
        }
        nudge.userResponseRaw = response.rawValue
        nudge.respondedAt = Date()
        nudge.statusRaw = NudgeStatus.responded.rawValue
        modelContext.safeSave()
    }
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
    // Calendar routing transparency: which calendar the last successful AI-created
    // event actually landed in, and whether to nudge the user to link Google the
    // first time we fall back to Apple. See CalendarResultChip.swift for why.
    @State private var lastCalendarTarget: CalendarTarget?
    @State private var showGoogleConnectBanner = false
    @State private var showingCalendarSettings = false
    @AppStorage("hasSeenGoogleConnectNudge") private var hasSeenGoogleConnectNudge = false
    @FocusState private var isInputFocused: Bool
    @State private var taskBuilder = TaskBuilderState()
    @State private var showReSignIn = false
    @State private var isReSigningIn = false
    // Re-entrancy guard for task builder chip taps. Double-tapping the
    // Done/Skip chip fast enough could fire the onSelect closure twice
    // (stale capture of selectedDimensions/step from the previous render),
    // producing duplicate "Done" user bubbles and duplicated confirm
    // prompts in the transcript. 150ms is long enough to absorb a human
    // double-tap, short enough that deliberate consecutive dimension
    // picks still pass through (BUG-01 from the Skip/Done QA pass).
    @State private var lastChipTapAt: Date = .distantPast
    /// Handle for the in-flight send so `.onDisappear` can cancel it.
    /// Without this, closing the chat while a response was streaming left
    /// the network request running and the state-mutation tail would fire
    /// against a view that was already gone.
    @State private var sendTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            // Pinned nudge — the Coach tab's primary receipt surface.
            // Renders only when there's a delivered nudge the user
            // hasn't reacted to. Once they tap 👍/👎 the card drops
            // because userResponseRaw changes and the @Query filter
            // stops matching. Conditional rendering keeps the
            // transcript flush to the header when there's nothing
            // waiting.
            if let nudge = pinnedNudge {
                PinnedNudgeCard(nudge: nudge) { response in
                    recordNudgeResponse(nudge: nudge, response: response)
                }
            }

            // Messages — tap to stop AI speech. `suppressJumpButton`
            // hides the floating scroll-to-bottom affordance while any
            // transient banner (re-sign-in, error, clock prompt,
            // calendar chip / confirmation, Google connect) or the
            // task-builder chip bar is visible — otherwise the button
            // lands atop the banner's top edge and looks broken.
            ConversationMessages(
                conversationID: conversationID,
                isAITyping: isAITyping,
                suppressJumpButton: showReSignIn
                    || errorMessage != nil
                    || showClockAppPrompt
                    || lastCalendarTarget != nil
                    || showGoogleConnectBanner
                    || !pendingCalendarActions.isEmpty
                    || (taskBuilder.isActive && !taskBuilder.chips.isEmpty)
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
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
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
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
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
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss")
                }
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accentLight)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Calendar routing chip — names the destination of the last successful
            // AI-created event so the user knows Apple vs Google.
            if let target = lastCalendarTarget, target != .none {
                CalendarResultChip(target: target)
            }

            // One-time Google connect nudge — only fires after an Apple fallback
            // when no Google link exists. hasSeenGoogleConnectNudge ensures once.
            if showGoogleConnectBanner {
                GoogleConnectBanner(
                    onConnect: {
                        hasSeenGoogleConnectNudge = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showGoogleConnectBanner = false
                        }
                        showingCalendarSettings = true
                    },
                    onDismiss: {
                        hasSeenGoogleConnectNudge = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showGoogleConnectBanner = false
                        }
                    }
                )
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
            // Cancel any in-flight send so we don't burn the response into
            // state on a view that's already gone.
            sendTask?.cancel()
            sendTask = nil
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
        .sheet(isPresented: $showingCalendarSettings) {
            NavigationStack {
                CalendarSettingsView()
                    .navigationTitle("Calendar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingCalendarSettings = false }
                        }
                    }
            }
        }
        // Auto-dismiss the calendar routing chip after a few seconds. Using
        // .task(id:) auto-cancels when target changes (next event fires before
        // the current chip is done).
        .task(id: lastCalendarTarget) {
            guard lastCalendarTarget != nil else { return }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return } // CancellationError = new target set; exit cleanly
            withAnimation(.easeInOut(duration: 0.3)) {
                lastCalendarTarget = nil
            }
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
                        .scaleEffect(reduceMotion ? 1.0 : (micPulse ? 1.3 : 0.8))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: micPulse
                        )
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
                    // Keyboard dismiss: drag-to-dismiss via
                    // .scrollDismissesKeyboard on the ConversationMessages
                    // ScrollView (above), plus focus is cleared on send.
                    // The Done toolbar button was removed because it
                    // rendered in the keyboard accessory bar at the same
                    // visual height as the orb button, creating a
                    // confusing double-button appearance.

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
                                .scaleEffect(reduceMotion ? 1.0 : (micPulse ? 1.2 : 1.0))
                                .opacity(reduceMotion ? 0.6 : (micPulse ? 0.0 : 0.6))
                                .animation(
                                    reduceMotion ? nil : .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: micPulse
                                )
                        }

                        // All three states share the same 44pt frame + drop
                        // shadow so the button reads as one control morphing
                        // between fills, not three different controls.
                        if hasText && !speechRecognizer.isRecording {
                            // Send state — accent-filled circle with white arrow
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 44, height: 44)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        } else if speechRecognizer.isRecording {
                            // Recording state — coral-filled circle with white compass mark
                            Circle()
                                .fill(AppColors.coral)
                                .frame(width: 44, height: 44)
                            ThrivnCompassMark(
                                color: .white,
                                size: 33,
                                isAnimating: true
                            )
                        } else {
                            // Idle state — Thrivn AI presence mark.
                            AIPresenceIcon(size: 44)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 2)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(actionButtonAccessibilityLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
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
        // before falling through to the AI. Supports typed dates ("friday", "tomorrow"),
        // times ("11:08pm", "9am"), and dimensions ("physical", "mental and emotional",
        // "skip") so users aren't forced to tap chips.
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
            } else if taskBuilder.step == .dimension {
                // BUG-05 fix: typing "physical", "mental and emotional", "skip",
                // etc. on the dimension step used to echo as a user bubble then
                // dead-end with "I didn't catch that". Parse it into state instead.
                handled = taskBuilder.setDimensionsFromText(text)
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
        sendTask?.cancel()
        sendTask = Task {
            // ChatManager handles: insert user msg → fetch history → build split prompt
            // (cached stable + uncached volatile) → call provider → parse tags →
            // insert assistant msg → record usage with cache token weighting → persist
            // activity entries → insert error messages on failure.
            let result = await chatManager.sendMessage(text, conversationID: convoID)

            // If the view disappeared while the request was in flight, stop
            // here — assistant message is already persisted by ChatManager.
            guard !Task.isCancelled else { return }

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
        // Re-entrancy guard — drop taps landing within 150ms of the prior
        // tap. See `lastChipTapAt` declaration for why.
        let now = Date()
        guard now.timeIntervalSince(lastChipTapAt) >= 0.15 else { return }
        lastChipTapAt = now

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

            ForEach(pendingCalendarActions, id: \.stableID) { action in
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

        /// Stable string key for ForEach identity. Using `id: \.offset`
        /// on an enumerated mutable array is prohibited because index
        /// shifts on insert/delete destroy row identity (QA BUG-05).
        var stableID: String {
            switch self {
            case .create(let title, let start, _, _, _, _):
                return "create_\(title)_\(start.timeIntervalSince1970)"
            case .delete(let eventID):
                return "delete_\(eventID)"
            }
        }
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
        let hasGoogleLink = googleCalendarID != nil

        // Track which calendar path actually succeeded for at least one event,
        // so we can surface the right chip after the batch completes. Only
        // successful creates count — catch blocks don't flip these, so a sync
        // failure leaves the chip silent (errorMessage path handles it).
        var createdInGoogle = false
        var createdInApple = false

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
                            createdInGoogle = true
                        } else if appleCalendarID != nil || syncManager.appleCalendarAuthorized {
                            let eventID = try await syncManager.eventKitService.createEvent(
                                title: title,
                                startDate: start,
                                endDate: end,
                                notes: description,
                                calendarID: appleCalendarID
                            )
                            calendarID = eventID
                            createdInApple = true
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

        // After the batch, surface which calendar the events landed in and
        // (first time only, Apple-only users) nudge toward Google.
        // Google wins over Apple if — for some reason — both fired in one
        // batch; realistically only one path runs per run given the
        // if/else-if structure above.
        let target: CalendarTarget
        if createdInGoogle {
            target = .google
        } else if createdInApple {
            target = .apple
        } else {
            target = .none
        }

        let shouldNudgeGoogle =
            target == .apple &&
            !hasSeenGoogleConnectNudge &&
            !hasGoogleLink

        await MainActor.run {
            if target != .none {
                withAnimation(.easeInOut(duration: 0.25)) {
                    lastCalendarTarget = target
                }
            }
            if shouldNudgeGoogle {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showGoogleConnectBanner = true
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

        // Bug fix #4: try multiple time formats to handle "7:00" as well as "07:00".
        // Formatters are cached once at module-load time via AlarmTimeFormatters
        // — previously a fresh DateFormatter was allocated for each format
        // attempt (up to 5× per alarm), which the dont-do list explicitly bans.
        var parsedTime: Date?
        for formatter in AlarmTimeFormatters.all {
            if let d = formatter.date(from: alarm.timeString) { parsedTime = d; break }
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
    let suppressJumpButton: Bool

    @Query private var messages: [ChatMessage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(conversationID: String, isAITyping: Bool, suppressJumpButton: Bool = false) {
        self.conversationID = conversationID
        self.isAITyping = isAITyping
        self.suppressJumpButton = suppressJumpButton
        let convoID = conversationID
        self._messages = Query(
            filter: #Predicate<ChatMessage> { $0.conversationID == convoID },
            sort: \ChatMessage.timestamp
        )
    }

    /// Rendered window — cap at the most recent 200 messages so a power
    /// user with 1000+ messages doesn't incur LazyVStack traversal +
    /// memory spike on every jump-to-bottom. "Load earlier" button
    /// expands the window by another 200 when requested. Raw `messages`
    /// is still the Codable source of truth; this only scopes rendering.
    @State private var renderedWindow: Int = 200

    private var visibleMessages: [ChatMessage] {
        guard messages.count > renderedWindow else { return Array(messages) }
        return Array(messages.suffix(renderedWindow))
    }

    private var hasHiddenHistory: Bool {
        messages.count > renderedWindow
    }

    /// True when the bottom-anchor sentinel is on-screen.
    /// Defaults true because `.defaultScrollAnchor(.bottom)` on the
    /// ScrollView positions us at the bottom on first render, so the
    /// anchor is visible immediately. `didInitialScroll` is latched
    /// by the anchor's own `onAppear` (meaning "the anchor really has
    /// been visible"), which gates the jump button so it never flashes
    /// on cold-launch before position is confirmed.
    @State private var isNearBottom: Bool = true
    @State private var didInitialScroll: Bool = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messages.isEmpty {
                        emptyState
                    }

                    if hasHiddenHistory {
                        Button {
                            renderedWindow += 200
                        } label: {
                            Text("Load earlier messages")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.accent)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(visibleMessages, id: \.id) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    if isAITyping {
                        typingIndicator
                            .id("typing")
                    }

                    // Bottom anchor sentinel: LazyVStack only renders
                    // this when it's in the viewport, so
                    // onAppear/onDisappear cleanly track "is the user at
                    // the bottom of the transcript?" without scroll-
                    // offset plumbing.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                        .onAppear {
                            isNearBottom = true
                            // First time the anchor is visible: initial
                            // scroll position is confirmed. Unlocks the
                            // jump button (gated on didInitialScroll) so
                            // it never flashes before we know scroll state.
                            didInitialScroll = true
                        }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                // Reserve extra space only when the jump-to-bottom
                // button will actually appear. At the bottom of the
                // transcript, or while any banner is suppressing the
                // button, the 12pt baseline matches the chip-bar
                // breathing room. `.animation(nil, value:)` cancels
                // the inherited animation on the overlay-fade modifier
                // below so the padding changes discretely — without
                // this, the last message slides 60pt whenever the
                // anchor crosses the viewport edge (QA BUG-01).
                // Collapsing when `suppressJumpButton` is true closes
                // the gap a banner would otherwise leave beneath the
                // reserved space (QA BUG-03).
                .padding(.bottom, (isNearBottom || suppressJumpButton) ? 12 : 72)
                .animation(nil, value: isNearBottom)
                .animation(nil, value: suppressJumpButton)
            }
            // Pin the scroll view's resting position to the bottom of
            // content. This handles two problems in one:
            // (a) keyboard show/hide resizes the viewport — iOS keeps
            //     the bottom content visible instead of jumping; and
            // (b) new messages that push content down stay in view
            //     without requiring a manual scrollTo call.
            // scrollDismissesKeyboard provides the interactive-drag
            // dismiss in lieu of the Done toolbar button, matching the
            // Messages/Slack pattern the user expects.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if !isNearBottom && !messages.isEmpty && !suppressJumpButton && didInitialScroll {
                    Button {
                        // Selection-style haptic matches the rest of the
                        // app's navigation affordances (tab switches,
                        // conversation switches) — reserving `.light()`
                        // for confirmation-style feedback (BUG-08).
                        Haptics.selection()
                        if let last = messages.last {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(AppColors.surface)
                                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
                            )
                            .overlay(
                                Circle()
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                    .accessibilityLabel("Scroll to latest message")
                    .accessibilityHint("Jumps to the most recent message")
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.85))
                    )
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isNearBottom)
            .task {
                // Fallback for the race where .defaultScrollAnchor
                // renders before @Query populates (empty messages on
                // first frame). If messages arrive before the anchor
                // fires onAppear, scroll explicitly. didInitialScroll
                // is set by the anchor itself; the task only scrolls.
                guard !didInitialScroll, let last = messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
                isNearBottom = true
            }
            // Re-fires whenever conversationID changes so that switching
            // conversations always lands at the new transcript's bottom.
            // Using .task(id:) is safer than onChange because it cancels
            // the previous task automatically and yields one run-loop
            // turn — enough for the new @Query results to populate before
            // we scroll, eliminating the stale-scroll race (QA BUG-01/02)
            // where onChange(conversationID) fired with the old messages
            // list and scrolled to the wrong conversation's last message.
            .task(id: conversationID) {
                didInitialScroll = false
                isNearBottom = true
                // Yield so the @Query result for the new conversationID
                // replaces the old list before we attempt to scroll.
                do { try await Task.sleep(for: .milliseconds(32)) }
                catch { return }
                guard !Task.isCancelled else { return }
                guard let last = messages.last,
                      last.conversationID == conversationID else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
                isNearBottom = true
            }
            .onChange(of: messages.count) { _, _ in
                // Fallback for the @Query race. Guard ensures we only
                // scroll when the messages in scope actually belong to
                // the current conversation — prevents the stale-data
                // jump when @Query briefly holds the old list.
                if !didInitialScroll,
                   let last = messages.last,
                   last.conversationID == conversationID {
                    proxy.scrollTo(last.id, anchor: .bottom)
                    isNearBottom = true
                    return
                }
                // Only auto-follow new messages if the user is already
                // near the bottom. When they've scrolled up to re-read
                // earlier messages, respect their reading position —
                // the floating jump button is the explicit way back
                // down.
                if isNearBottom, let last = messages.last {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                    isNearBottom = true
                }
            }
            .onChange(of: isAITyping) { _, typing in
                // Same gate as messages.count — don't yank the scroll
                // position when the user is reading history.
                if typing && isNearBottom {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                    isNearBottom = true
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
                // Reduce Motion: render three static dots (WCAG 2.3.3 —
                // avoid repeating animations) + an "assistant is typing"
                // accessibility label so VoiceOver announces the state.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(AppColors.textMuted)
                        .frame(width: 7, height: 7)
                        .opacity(reduceMotion ? 0.5 : 0.5)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.6)
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
            .accessibilityElement()
            .accessibilityLabel("Assistant is typing")

            Spacer()
        }
    }
}

/// Cached formatters for alarm time-string parsing in `scheduleAlarm`.
/// Allocating 5 new DateFormatters per alarm (the old pattern) violated
/// the dont-do rule and cost ~10ms per alarm for no reason — these are
/// immutable and safe to share at file scope.
private enum AlarmTimeFormatters {
    static let all: [DateFormatter] = ["HH:mm", "H:mm", "h:mm a", "h:mma", "h:mm"].map {
        let f = DateFormatter()
        f.dateFormat = $0
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }
}

// MARK: - Pinned nudge card

/// Compact version of `RecentNudgeRow` (defined in CoachSettingsView)
/// sized for the Coach tab's persistent position above the transcript.
/// Kept private + inline for commit-2 scope — if a third caller needs
/// it, extract to Views/Components then. Behavior mirrors the Settings
/// receipt: thumbs-up/down for normal nudges, amber tint + Link to
/// SafeResourceCopy.actionURL for safetyRoute (asking "was that helpful"
/// after a safety intervention is tone-deaf; see crisis-safety-protocols).
private struct PinnedNudgeCard: View {
    let nudge: Nudge
    let onReact: (UserNudgeResponse) -> Void

    private var isSafety: Bool { nudge.category == .safetyRoute }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(categoryBadge(nudge.category))
                    .font(AppFonts.label(11))
                    .foregroundColor(isSafety ? AppColors.warning : AppColors.accent)
                Text("·")
                    .foregroundColor(AppColors.textMuted)
                Text(nudge.createdAt, style: .relative)
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
                Spacer()
            }

            Text(nudge.bodyText)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if isSafety {
                Link(destination: SafeResourceCopy.actionURL()) {
                    Label(SafeResourceCopy.actionTitle, systemImage: "arrow.up.right.square")
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(AppColors.warning)
            } else {
                HStack(spacing: 10) {
                    Button {
                        Haptics.selection()
                        onReact(.accepted)
                    } label: {
                        Label("Helpful", systemImage: "hand.thumbsup")
                            .font(AppFonts.bodyMedium(13))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.accent)

                    Button {
                        Haptics.selection()
                        onReact(.dismissed)
                    } label: {
                        Label("Not helpful", systemImage: "hand.thumbsdown")
                            .font(AppFonts.bodyMedium(13))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.textMuted)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSafety ? AppColors.warningBg : AppColors.accentLight.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSafety ? AppColors.warning.opacity(0.35) : AppColors.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func categoryBadge(_ category: NudgeCategory) -> String {
        switch category {
        case .weakDimension:     return "WEAK AREA"
        case .streakAtRisk:      return "STREAK"
        case .calendarGap:       return "RESET"
        case .habitSlip:         return "HABIT"
        case .postCheckInAction: return "CHECK-IN"
        case .goalCheckpoint:    return "GOAL"
        case .safetyRoute:       return "SUPPORT"
        }
    }
}
