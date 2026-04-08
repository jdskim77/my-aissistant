import SwiftUI
import UserNotifications

struct NotificationPermissionView: View {
    let onAllow: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(AppFonts.icon(64))
                    .foregroundColor(AppColors.accent)
                    .scaleEffect(appeared ? 1 : 0.6)

                VStack(spacing: 12) {
                    Text("Want gentle reminders?")
                        .font(AppFonts.display(28))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("I'll send a quiet nudge for each check-in. No spam, no marketing.")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 14) {
                    benefitRow(
                        icon: "bell.fill",
                        title: "4 check-ins a day",
                        subtitle: "Morning, midday, afternoon, night"
                    )
                    benefitRow(
                        icon: "flame.fill",
                        title: "Streak protection",
                        subtitle: "I'll let you know if your streak is at risk"
                    )
                    benefitRow(
                        icon: "hand.raised.fill",
                        title: "You're in control",
                        subtitle: "Turn off any time in Settings"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(action: requestPermission) {
                    Text(requesting ? "Requesting…" : "Enable Reminders")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }
                .disabled(requesting)
                .accessibilityHint("Asks for notification permission")

                Button(action: {
                    Haptics.selection()
                    onSkip()
                }) {
                    Text("Not now")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Skips this step and continues")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(appeared ? 1 : 0)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            await MainActor.run {
                requesting = false
                if granted {
                    Haptics.success()
                } else {
                    Haptics.light()
                }
                // Always advance — the system prompt has been shown.
                onAllow()
            }
        }
    }

    private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFonts.bodyMedium(18))
                .foregroundColor(AppColors.accent)
                .frame(width: 36, height: 36)
                .background(AppColors.accent.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
            Spacer()
        }
    }
}
