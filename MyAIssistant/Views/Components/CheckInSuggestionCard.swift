import SwiftUI

struct CheckInSuggestionCard: View {
    let suggestion: CheckInSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: suggestion.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accentColor)

                Text("Suggestion")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(suggestion.reason)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let timeStr = suggestion.suggestedTimeString {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(timeStr)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(accentColor)
            }

            HStack(spacing: 12) {
                Button(action: onAccept) {
                    Text(acceptLabel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var accentColor: Color {
        switch suggestion.type {
        case .disableWindow: return .orange
        case .adjustTime: return AppColors.accent
        case .addWindow: return AppColors.completionGreen
        }
    }

    private var acceptLabel: String {
        switch suggestion.type {
        case .disableWindow: return "Skip it"
        case .adjustTime: return "Adjust time"
        case .addWindow: return "Add check-in"
        }
    }
}
