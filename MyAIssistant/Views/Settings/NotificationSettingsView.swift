import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    // Persisted preferences. Stored as Double (TimeInterval) so AppStorage works for Date.
    // Default values map to: 8:00, 13:00, 18:00, 22:00 local time.
    @AppStorage("notif.checkInReminders") private var checkInReminders = true
    @AppStorage("notif.taskAlerts") private var taskAlerts = true
    @AppStorage("notif.morningTime") private var morningTimeRaw: Double = Self.defaultTimeInterval(hour: 8)
    @AppStorage("notif.middayTime") private var middayTimeRaw: Double = Self.defaultTimeInterval(hour: 13)
    @AppStorage("notif.afternoonTime") private var afternoonTimeRaw: Double = Self.defaultTimeInterval(hour: 18)
    @AppStorage("notif.nightTime") private var nightTimeRaw: Double = Self.defaultTimeInterval(hour: 22)

    @State private var notificationsEnabled = false
    @State private var showSavedConfirmation = false

    private var morningTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: morningTimeRaw) },
            set: { morningTimeRaw = $0.timeIntervalSince1970 }
        )
    }
    private var middayTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: middayTimeRaw) },
            set: { middayTimeRaw = $0.timeIntervalSince1970 }
        )
    }
    private var afternoonTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: afternoonTimeRaw) },
            set: { afternoonTimeRaw = $0.timeIntervalSince1970 }
        )
    }
    private var nightTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: nightTimeRaw) },
            set: { nightTimeRaw = $0.timeIntervalSince1970 }
        )
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                        .font(AppFonts.icon(20))
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
                    checkInTimeRow("Morning", icon: "🌅", time: morningTime)
                    checkInTimeRow("Midday", icon: "☀️", time: middayTime)
                    checkInTimeRow("Afternoon", icon: "🌤️", time: afternoonTime)
                    checkInTimeRow("Night", icon: "🌙", time: nightTime)
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
                            .font(AppFonts.body(14))
                        Text("Update Notification Schedule")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                if showSavedConfirmation {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.completionGreen)
                        Text("Schedule updated")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.completionGreen)
                    }
                    .frame(maxWidth: .infinity)
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
                .font(AppFonts.icon(20))
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
        Haptics.success()
        withAnimation { showSavedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showSavedConfirmation = false }
        }
    }

    /// Default time stored as a TimeInterval relative to today at the given hour.
    /// Only the hour/minute components are read by `DatePicker(displayedComponents: .hourAndMinute)`.
    private static func defaultTimeInterval(hour: Int) -> Double {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        return (Calendar.current.date(from: components) ?? Date()).timeIntervalSince1970
    }
}
