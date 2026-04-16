import SwiftUI

/// Which calendar an AI-created event actually landed in.
///
/// Why this exists: ChatManager silently picks Google when any Google link is
/// enabled, else falls back to Apple. External testers were seeing "added to
/// your calendar" confirmations and couldn't tell whether the event went to
/// the Google Calendar they live in or an Apple Calendar they never opened.
/// Surfacing the target closes that loop.
enum CalendarTarget: Equatable {
    case google
    case apple
    case none
}

/// Transient chip rendered below the chat message area after an AI-created
/// calendar event succeeds. Names the destination explicitly so the user can
/// trust where the AI put it.
struct CalendarResultChip: View {
    let target: CalendarTarget

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
            Text(label)
                .font(AppFonts.bodyMedium(13))
            Spacer()
        }
        .foregroundColor(AppColors.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.accent.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var label: String {
        switch target {
        case .google: return "Added to Google Calendar"
        case .apple: return "Added to Apple Calendar"
        case .none: return ""
        }
    }
}

/// One-time nudge shown after the first Apple-only fallback when the user
/// hasn't linked Google. `hasSeenGoogleConnectNudge` in UserDefaults ensures
/// it never fires twice — once dismissed (either via Connect or Not now),
/// the flag is set and the banner stays quiet forever.
struct GoogleConnectBanner: View {
    let onConnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Also use Google Calendar?")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(AppColors.textPrimary)
                Text("Connect it so AI edits land where you actually live.")
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            }

            Spacer(minLength: 8)

            Button(action: onConnect) {
                Text("Connect")
                    .font(AppFonts.bodyMedium(12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.accent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Connect Google Calendar")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(6)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.accentLight)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
