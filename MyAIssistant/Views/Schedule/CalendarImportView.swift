import SwiftUI
import EventKit

struct CalendarImportView: View {
    @Environment(\.calendarSyncManager) private var calendarSyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Apple Calendar section
                    appleCalendarSection

                    // Google Calendar section
                    googleCalendarSection

                    // Linked calendars
                    linkedCalendarsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .offset(y: appeared ? 0 : 20)
                .opacity(appeared ? 1 : 0)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Import Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.accent)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
                Task {
                    if calendarSyncManager?.appleCalendarAuthorized == true {
                        await calendarSyncManager?.loadAppleCalendars()
                    }
                }
            }
        }
    }

    // MARK: - Apple Calendar Section

    private var appleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.accent)
                Text("Apple Calendar")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
            }

            if calendarSyncManager?.appleCalendarAuthorized == true {
                let calendars = calendarSyncManager?.appleCalendars ?? []
                if calendars.isEmpty {
                    Text("No calendars found.")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { cal in
                        calendarRow(
                            name: cal.title,
                            color: Color(cgColor: cal.cgColor),
                            isLinked: isLinked(calendarID: cal.calendarIdentifier, source: .apple)
                        ) {
                            toggleLink(calendar: cal)
                        }
                    }
                }
            } else {
                Button {
                    Task {
                        _ = await calendarSyncManager?.requestAppleCalendarAccess()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open")
                            .font(.system(size: 14, weight: .medium))
                        Text("Grant Calendar Access")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.accent)
                    .cornerRadius(10)
                }
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

    // MARK: - Google Calendar Section

    private var googleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.coral)
                Text("Google Calendar")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
            }

            Text("Google Calendar integration requires a configured OAuth client. Coming soon.")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textMuted)
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Linked Calendars

    private var linkedCalendarsSection: some View {
        let links = calendarSyncManager?.linkedCalendars() ?? []

        return Group {
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Synced Calendars")
                        .font(AppFonts.heading(17))
                        .foregroundColor(AppColors.textPrimary)

                    ForEach(links, id: \.id) { link in
                        HStack(spacing: 12) {
                            Image(systemName: link.calendarSource.icon)
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.name)
                                    .font(AppFonts.bodyMedium(14))
                                    .foregroundColor(AppColors.textPrimary)
                                if let synced = link.lastSynced {
                                    Text("Last synced: \(synced.formatted(as: "MMM d, h:mm a"))")
                                        .font(AppFonts.caption(11))
                                        .foregroundColor(AppColors.textMuted)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { link.enabled },
                                set: { _ in calendarSyncManager?.toggleCalendarLink(link) }
                            ))
                            .labelsHidden()
                            .tint(AppColors.accent)
                        }
                        .padding(12)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                    }

                    // Sync now button
                    Button {
                        Task { await calendarSyncManager?.syncAll() }
                    } label: {
                        HStack(spacing: 6) {
                            if calendarSyncManager?.isSyncing == true {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text("Sync Now")
                                .font(AppFonts.bodyMedium(14))
                        }
                        .foregroundColor(AppColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.accentLight)
                        .cornerRadius(10)
                    }
                    .disabled(calendarSyncManager?.isSyncing == true)
                }
                .padding(16)
                .background(AppColors.card)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private func calendarRow(
        name: String,
        color: Color,
        isLinked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(name)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Button {
                action()
            } label: {
                Text(isLinked ? "Linked" : "Link")
                    .font(AppFonts.bodyMedium(13))
                    .foregroundColor(isLinked ? AppColors.accentWarm : AppColors.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(isLinked ? AppColors.accentWarm.opacity(0.1) : AppColors.accentLight)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }

    private func isLinked(calendarID: String, source: CalendarSource) -> Bool {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        return links.contains { $0.calendarID == calendarID && $0.source == source.rawValue }
    }

    private func toggleLink(calendar: EKCalendar) {
        let links = calendarSyncManager?.linkedCalendars() ?? []
        if let existing = links.first(where: { $0.calendarID == calendar.calendarIdentifier && $0.source == CalendarSource.apple.rawValue }) {
            calendarSyncManager?.unlinkCalendar(existing)
        } else {
            let components = calendar.cgColor.components ?? [0, 0.3, 0.1, 1]
            let hex = String(format: "#%02X%02X%02X",
                             Int((components[safe: 0] ?? 0) * 255),
                             Int((components[safe: 1] ?? 0) * 255),
                             Int((components[safe: 2] ?? 0) * 255))
            calendarSyncManager?.linkCalendar(
                source: .apple,
                calendarID: calendar.calendarIdentifier,
                name: calendar.title,
                color: hex
            )
        }
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
