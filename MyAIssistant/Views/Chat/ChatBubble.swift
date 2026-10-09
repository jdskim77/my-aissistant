import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    /// Whether to render the timestamp label under this bubble. Hidden
    /// for messages grouped with the previous one (same sender, within
    /// 5 minutes) per `MessageGrouping` — avoids a timestamp under every
    /// single bubble in a back-to-back burst (Impeccable Screens audit
    /// P2: "group consecutive messages and show one time per group").
    var showTimestamp: Bool = true

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(AppFonts.body(15))
                    .foregroundColor(isUser ? AppColors.userBubbleText : AppColors.aiBubbleText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        isUser
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [AppColors.accent, AppColors.accentWarm],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                              )
                            : AnyShapeStyle(AppColors.aiBubble)
                    )
                    .cornerRadius(18)
                    .overlay(
                        !isUser
                            ? RoundedRectangle(cornerRadius: 18)
                                .stroke(AppColors.aiBubbleBorder, lineWidth: 1)
                            : nil
                    )
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy Message", systemImage: "doc.on.doc")
                        }
                    }

                if showTimestamp {
                    Text(formatTime(message.timestamp))
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(as: "h:mm a")
    }
}
