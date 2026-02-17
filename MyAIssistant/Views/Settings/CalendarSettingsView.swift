import SwiftUI

struct CalendarSettingsView: View {
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @State private var showingImport = false

    var body: some View {
        List {
            // Connection status
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Calendar")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Text(calendarSyncManager?.appleCalendarAuthorized == true ? "Connected" : "Not connected")
                            .font(AppFonts.caption(13))
                            .foregroundColor(calendarSyncManager?.appleCalendarAuthorized == true ? AppColors.accentWarm : AppColors.textMuted)
                    }

                    Spacer()

                    if calendarSyncManager?.appleCalendarAuthorized == true {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.accentWarm)
                    }
                }

                HStack(spacing: 14) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.coral)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Calendar")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.textPrimary)
                        Text("Not configured")
                            .font(AppFonts.caption(13))
                            .foregroundColor(AppColors.textMuted)
                    }

                    Spacer()
                }
            } header: {
                Text("Calendar Sources")
            }

            // Linked calendars
            Section {
                let links = calendarSyncManager?.linkedCalendars() ?? []
                if links.isEmpty {
                    Text("No calendars linked. Tap 'Manage Calendars' to get started.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                } else {
                    ForEach(links, id: \.id) { link in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: link.color))
                                .frame(width: 10, height: 10)

                            Text(link.name)
                                .font(AppFonts.body(14))
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { link.enabled },
                                set: { _ in calendarSyncManager?.toggleCalendarLink(link) }
                            ))
                            .labelsHidden()
                            .tint(AppColors.accent)
                        }
                    }
                }
            } header: {
                Text("Linked Calendars")
            }

            // Actions
            Section {
                Button {
                    showingImport = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(AppColors.accent)
                        Text("Manage Calendars")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.accent)
                    }
                }

                Button {
                    Task { await calendarSyncManager?.syncAll() }
                } label: {
                    HStack(spacing: 10) {
                        if calendarSyncManager?.isSyncing == true {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(AppColors.accent)
                        }
                        Text("Sync Now")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(AppColors.accent)
                    }
                }
                .disabled(calendarSyncManager?.isSyncing == true)
            } header: {
                Text("Actions")
            }

            // Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How Calendar Sync Works")
                        .font(AppFonts.bodyMedium(14))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Events from linked calendars appear as tasks in your schedule. Tasks created in the app can be pushed to Apple Calendar. Google Calendar sync is read-only.")
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Calendar Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImport) {
            CalendarImportView()
        }
    }
}
