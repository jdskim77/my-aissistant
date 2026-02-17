import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @State private var notificationsEnabled = false
    @State private var checkInReminders = true
    @State private var taskAlerts = true
    @State private var morningTime = defaultTime(hour: 8)
    @State private var middayTime = defaultTime(hour: 13)
    @State private var afternoonTime = defaultTime(hour: 18)
    @State private var nightTime = defaultTime(hour: 22)

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                        .font(.system(size: 20))
                        .foregroundColor(notificationsEnabled ? AppColors.accentWarm : AppColors.textMuted)
                        .frame(width: 28)

                    Text("Notifications")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    if notificationsEnabled {
                        Text("Enabled")
                            .font(AppFonts.caption(13))
                            .foregroundColor(AppColors.accentWarm)
                    } else {
                        Button("Enable") {
                            requestPermission()
                        }
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.accent)
                    }
                }
            } header: {
                Text("Status")
            }

            Section {
                Toggle(isOn: $checkInReminders) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        Text("Check-in Reminders")
                            .font(AppFonts.body(15))
                    }
                }
                .tint(AppColors.accent)

                Toggle(isOn: $taskAlerts) {
                    HStack(spacing: 10) {
                        Image(systemName: "checklist")
                            .foregroundColor(AppColors.accentWarm)
                            .frame(width: 24)
                        Text("Task Due Alerts")
                            .font(AppFonts.body(15))
                    }
                }
                .tint(AppColors.accent)
            } header: {
                Text("Notification Types")
            }

            if checkInReminders {
                Section {
                    checkInTimeRow("Morning", icon: "🌅", time: $morningTime)
                    checkInTimeRow("Midday", icon: "☀️", time: $middayTime)
                    checkInTimeRow("Afternoon", icon: "🌤️", time: $afternoonTime)
                    checkInTimeRow("Night", icon: "🌙", time: $nightTime)
                } header: {
                    Text("Check-in Times")
                } footer: {
                    Text("You'll receive a notification at each time to start your check-in.")
                }
            }

            Section {
                Button {
                    rescheduleNotifications()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 14))
                        Text("Update Notification Schedule")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkNotificationStatus()
        }
    }

    private func checkInTimeRow(_ label: String, icon: String, time: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 20))
            Text(label)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .tint(AppColors.accent)
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    private func requestPermission() {
        Task {
            let manager = NotificationManager()
            let granted = await manager.requestAuthorization()
            await MainActor.run {
                notificationsEnabled = granted
            }
        }
    }

    private func rescheduleNotifications() {
        let manager = NotificationManager()
        manager.scheduleCheckInReminders()
    }

    private static func defaultTime(hour: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}
