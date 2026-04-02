import SwiftUI
import SwiftData

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp, order: .reverse) private var allMessages: [ChatMessage]
    @Binding var selectedConversationID: String
    @Environment(\.dismiss) private var dismiss

    private var conversations: [(id: String, title: String, lastDate: Date, messageCount: Int)] {
        let grouped = Dictionary(grouping: allMessages) { $0.conversationID }
        return grouped.compactMap { (id, messages) in
            guard let latest = messages.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            let title = conversationTitle(id: id, messages: messages)
            return (id: id, title: title, lastDate: latest.timestamp, messageCount: messages.count)
        }
        .sorted { $0.lastDate > $1.lastDate }
    }

    var body: some View {
        NavigationStack {
            List {
                // New conversation button
                Button {
                    let newID = UUID().uuidString
                    selectedConversationID = newID
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 32, height: 32)
                            .background(AppColors.accentLight)
                            .cornerRadius(8)

                        Text("New Conversation")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.accent)
                    }
                }
                .listRowBackground(AppColors.card)

                // Existing conversations
                ForEach(conversations, id: \.id) { convo in
                    Button {
                        selectedConversationID = convo.id
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: convo.id == "weekly-review" ? "sparkles" : "bubble.left.and.bubble.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(convo.id == selectedConversationID ? .white : AppColors.textMuted)
                                .frame(width: 32, height: 32)
                                .background(convo.id == selectedConversationID ? AppColors.accent : AppColors.surface)
                                .cornerRadius(8)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(convo.title)
                                    .font(AppFonts.bodyMedium(14))
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text("\(convo.messageCount) messages")
                                        .font(AppFonts.caption(11))
                                        .foregroundColor(AppColors.textMuted)

                                    Text("·")
                                        .foregroundColor(AppColors.textMuted)

                                    Text(convo.lastDate.formatted(as: "MMM d"))
                                        .font(AppFonts.caption(11))
                                        .foregroundColor(AppColors.textMuted)
                                }
                            }

                            Spacer()

                            if convo.id == selectedConversationID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                    }
                    .listRowBackground(AppColors.card)
                }
                .onDelete { indexSet in
                    deleteConversations(at: indexSet)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFonts.bodyMedium(15))
                }
            }
        }
    }

    private func conversationTitle(id: String, messages: [ChatMessage]) -> String {
        if id == "main" { return "Main Chat" }
        if id == "weekly-review" { return "Weekly Reviews" }
        // Use first user message as title
        if let firstUser = messages.sorted(by: { $0.timestamp < $1.timestamp }).first(where: { $0.role == .user }) {
            let preview = firstUser.content.prefix(40)
            return preview.count < firstUser.content.count ? "\(preview)..." : String(preview)
        }
        return "Conversation"
    }

    private func deleteConversations(at offsets: IndexSet) {
        for index in offsets {
            let convoID = conversations[index].id
            guard convoID != "main" else { continue } // Don't delete main
            let messages = allMessages.filter { $0.conversationID == convoID }
            for message in messages {
                modelContext.delete(message)
            }
        }
        modelContext.safeSave()
    }
}
