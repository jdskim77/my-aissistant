import SwiftUI

struct SettingsView: View {
    @Environment(\.subscriptionTier) private var tier
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            List {
                // Appearance
                Section {
                    NavigationLink {
                        ThemePickerView()
                    } label: {
                        settingsRow(
                            icon: "paintpalette.fill",
                            color: AppColors.skyBlue,
                            title: "Appearance",
                            subtitle: ThemeManager.shared.selectedTheme.rawValue
                        )
                    }


                    NavigationLink {
                        TextSizeSettingsView()
                    } label: {
                        settingsRow(
                            icon: "textformat.size",
                            color: AppColors.gold,
                            title: "Text Size",
                            subtitle: TextSizeManager.shared.selectedSize.rawValue
                        )
                    }
                } header: {
                    Text("Appearance")
                }

                // Account & Subscription
                Section {
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        settingsRow(
                            icon: "crown.fill",
                            color: AppColors.accentWarm,
                            title: "Subscription",
                            subtitle: tier.displayName
                        )
                    }

                    NavigationLink {
                        APIKeySettingsView()
                    } label: {
                        settingsRow(
                            icon: "key.fill",
                            color: AppColors.accent,
                            title: "API Keys",
                            subtitle: "Manage your API keys"
                        )
                    }
                } header: {
                    Text("Account")
                }

                // App Settings
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        settingsRow(
                            icon: "bell.fill",
                            color: AppColors.coral,
                            title: "Notifications",
                            subtitle: "Check-in reminders & alerts"
                        )
                    }

                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        settingsRow(
                            icon: "waveform.circle.fill",
                            color: AppColors.accentWarm,
                            title: "Voice",
                            subtitle: "Voice mode & voice selection"
                        )
                    }

                    NavigationLink {
                        CalendarSettingsView()
                    } label: {
                        settingsRow(
                            icon: "calendar",
                            color: AppColors.accent,
                            title: "Calendar",
                            subtitle: "Manage calendar connections"
                        )
                    }
                } header: {
                    Text("Preferences")
                }

                // Permissions
                Section {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Label("Manage Permissions", systemImage: "lock.shield")
                                .font(AppFonts.body(15))
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text("Mic, Calendar, Notifications")
                                .font(AppFonts.caption(12))
                                .foregroundColor(AppColors.textMuted)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textMuted)
                        }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Opens iOS Settings to manage microphone, calendar, notification, and camera access.")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textMuted)
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .offset(y: appeared ? 0 : 10)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
        }
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .padding(.vertical, 2)
    }
}
