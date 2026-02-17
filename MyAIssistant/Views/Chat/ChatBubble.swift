import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(AppFonts.body(15))
                    .foregroundColor(isUser ? .white : AppColors.textPrimary)
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
                            : AnyShapeStyle(AppColors.surface)
                    )
                    .cornerRadius(18)
                    .overlay(
                        !isUser
                            ? RoundedRectangle(cornerRadius: 18)
                                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
                            : nil
                    )

                Text(formatTime(message.timestamp))
                    .font(AppFonts.caption(10))
                    .foregroundColor(AppColors.textMuted)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(as: "h:mm a")
    }
}
