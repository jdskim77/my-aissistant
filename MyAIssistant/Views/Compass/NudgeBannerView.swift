import SwiftUI

/// Inline nudge card shown on HomeView when a dimension needs attention.
/// Max 1 per day. Phrased as a suggestion, not a command.
struct NudgeBannerView: View {
    let nudge: BalanceManager.Nudge
    let onDismiss: () -> Void
    let onAddTask: (LifeDimension, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: nudge.dimension.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(nudge.dimension.color)

                Text(nudge.message)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.textMuted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss nudge")
            }

            Button {
                Haptics.light()
                onAddTask(nudge.dimension, nudge.suggestion)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                    Text(nudge.suggestion)
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(nudge.dimension.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(nudge.dimension.color.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task: \(nudge.suggestion)")
        }
        .padding(14)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(nudge.dimension.color.opacity(0.15), lineWidth: 1)
        )
    }
}
