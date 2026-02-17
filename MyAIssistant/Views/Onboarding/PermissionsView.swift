import SwiftUI

struct PermissionsView: View {
    let onContinue: () -> Void
    @State private var notificationsGranted: Bool?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text("🔔")
                    .font(.system(size: 56))

                Text("Stay on Track")
                    .font(AppFonts.display(28))
                    .foregroundColor(AppColors.textPrimary)

                Text("Enable notifications to receive check-in\nreminders and task alerts.")
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                // Notification permission card
                VStack(spacing: 16) {
                    permissionCard(
                        icon: "bell.badge.fill",
                        title: "Notifications",
                        subtitle: "Check-in reminders & task alerts",
                        granted: notificationsGranted
                    ) {
                        requestNotifications()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }

                Button(action: onContinue) {
                    Text("Skip for now")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textMuted)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func permissionCard(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(granted == true ? AppColors.accentWarm : AppColors.accent)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if granted == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.accentWarm)
            } else {
                Button("Enable") {
                    action()
                }
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppColors.accent)
                .cornerRadius(8)
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

    private func requestNotifications() {
        Task {
            let manager = NotificationManager()
            let granted = await manager.requestAuthorization()
            await MainActor.run {
                notificationsGranted = granted
                if granted {
                    manager.scheduleCheckInReminders()
                }
            }
        }
    }
}
