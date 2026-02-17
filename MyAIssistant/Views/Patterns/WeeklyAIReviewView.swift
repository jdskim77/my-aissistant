import SwiftUI
import SwiftData

struct WeeklyAIReviewView: View {
    @Environment(\.patternEngine) private var patternEngine
    @Environment(\.subscriptionTier) private var tier
    @Query(
        filter: #Predicate<ChatMessage> { $0.conversationID == "weekly-review" },
        sort: \ChatMessage.timestamp,
        order: .reverse
    ) private var reviews: [ChatMessage]

    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly AI Review")
                    .font(AppFonts.heading(16))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if tier != .free {
                    Button {
                        Task { await generateReview() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                    .disabled(isGenerating)
                }
            }

            if let latestReview = reviews.first(where: { $0.role == .assistant }) {
                Text(latestReview.content)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
                    .lineSpacing(4)

                Text(formattedDate(latestReview.timestamp))
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.gold)

                    Text("No weekly review yet")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textSecondary)

                    if tier == .free {
                        Text("Upgrade to Pro for AI weekly reviews")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                    } else {
                        Text("Your first review will generate on Sunday evening")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func generateReview() async {
        guard let engine = patternEngine else { return }
        isGenerating = true
        defer { isGenerating = false }
        await engine.generateWeeklyReview(tier: tier)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
