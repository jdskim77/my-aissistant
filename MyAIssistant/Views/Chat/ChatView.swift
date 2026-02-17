import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var tier
    @Environment(\.usageGateManager) private var usageGateManager
    @Environment(\.modelContext) private var modelContext
    @State private var conversationID = "main"
    @State private var inputText = ""
    @State private var isAITyping = false
    @State private var appeared = false
    @State private var errorMessage: String?
    @State private var showingConversations = false
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

            // Messages
            ConversationMessages(
                conversationID: conversationID,
                isAITyping: isAITyping
            )

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

            // Usage limit paywall
            if tier == .free, let gate = usageGateManager, !gate.canSendChat(tier: tier) {
                PaywallCard(
                    title: "Chat limit reached",
                    message: "You've used all \(AppConstants.freeChatMessagesPerMonth) free messages this month."
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
        }
        .sheet(isPresented: $showingConversations) {
            ConversationListView(selectedConversationID: $conversationID)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Text("✦")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }

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

    private var inputBar: some View {
        HStack(spacing: 12) {
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
                        .stroke(AppColors.border, lineWidth: 1)
                )

            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                sendMessage(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textMuted : AppColors.accent)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.surface)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        errorMessage = nil

        // Check usage gate
        if let gate = usageGateManager, !gate.canSendChat(tier: tier) {
            errorMessage = "Chat limit reached. Upgrade to Pro for unlimited messages."
            return
        }

        let userMessage = ChatMessage(role: .user, content: text, conversationID: conversationID)
        modelContext.insert(userMessage)
        try? modelContext.save()
        inputText = ""
        isInputFocused = false
        isAITyping = true

        Task {
            do {
                let provider = try AIProviderFactory.provider(
                    for: tier,
                    useCase: .chat,
                    keychain: keychainService
                )

                let systemPrompt = AIPromptBuilder.chatSystemPrompt(
                    scheduleSummary: taskManager?.scheduleSummary() ?? "",
                    completionRate: patternEngine?.completionRate() ?? 0,
                    streak: patternEngine?.currentStreak() ?? 0
                )

                // Fetch messages for this conversation for history
                let convoID = conversationID
                let descriptor = FetchDescriptor<ChatMessage>(
                    predicate: #Predicate { $0.conversationID == convoID },
                    sortBy: [SortDescriptor(\ChatMessage.timestamp)]
                )
                let history = (try? modelContext.fetch(descriptor)) ?? []

                let aiResponse = try await provider.sendMessage(
                    userMessage: text,
                    conversationHistory: Array(history.suffix(10)),
                    systemPrompt: systemPrompt
                )

                await MainActor.run {
                    isAITyping = false
                    let assistantMessage = ChatMessage(role: .assistant, content: aiResponse.content, conversationID: conversationID)
                    modelContext.insert(assistantMessage)

                    // Track usage
                    usageGateManager?.recordChatMessage(inputTokens: aiResponse.inputTokens, outputTokens: aiResponse.outputTokens)

                    try? modelContext.save()
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
                    } else {
                        let msg = ChatMessage(
                            role: .assistant,
                            content: "I'm having trouble connecting right now. Please check your API key and try again.",
                            conversationID: conversationID
                        )
                        modelContext.insert(msg)
                    }
                    try? modelContext.save()
                }
            }
        }
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
