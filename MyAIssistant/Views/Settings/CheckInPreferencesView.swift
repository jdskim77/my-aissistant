import SwiftUI

struct CheckInPreferencesView: View {
    @Environment(\.checkInBehaviorEngine) private var behaviorEngine
    @State private var preferences: [CheckInPreference] = []
    @State private var insights: [CheckInBehaviorEngine.WindowInsight] = []
    @State private var activeSuggestion: CheckInSuggestion?

    var body: some View {
        List {
            // Active suggestion
            if let suggestion = activeSuggestion {
                Section {
                    CheckInSuggestionCard(
                        suggestion: suggestion,
                        onAccept: { acceptSuggestion(suggestion) },
                        onDismiss: { dismissSuggestion(suggestion) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // Check-in windows
            Section {
                ForEach(preferences, id: \.id) { pref in
                    windowRow(pref)
                }
            } header: {
                Text("Your Windows")
            } footer: {
                Text("Toggle windows on or off. Adjust times within each window.")
            }

            // Insights
            if !insights.isEmpty {
                Section {
                    ForEach(insights) { insight in
                        insightRow(insight)
                    }
                } header: {
                    Text("Completion Insights")
                } footer: {
                    Text("Based on the last \(AppConstants.behaviorWindowDays) days of check-in activity.")
                }
            }
        }
        .navigationTitle("Check-in Schedule")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { refresh() }
    }

    // MARK: - Window Row

    @ViewBuilder
    private func windowRow(_ pref: CheckInPreference) -> some View {
        HStack(spacing: 12) {
            Text(pref.displayIcon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(pref.displayTitle)
                    .font(.body.weight(.medium))

                Text(pref.scheduledTimeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time picker (±2 hours from default)
            if pref.isEnabled, let checkInTime = pref.checkInTime {
                DatePicker(
                    "",
                    selection: timeBinding(for: pref),
                    in: timeRange(for: checkInTime),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .frame(width: 90)
            }

            Toggle("", isOn: enabledBinding(for: pref))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Insight Row

    @ViewBuilder
    private func insightRow(_ insight: CheckInBehaviorEngine.WindowInsight) -> some View {
        HStack(spacing: 12) {
            Text(insight.icon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.displayTitle)
                    .font(.body.weight(.medium))

                if insight.isEnabled {
                    Text("Avg time: \(insight.averageTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if insight.isEnabled {
                completionBadge(rate: insight.completionPercentage)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func completionBadge(rate: Int) -> some View {
        Text("\(rate)%")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(completionColor(rate))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(completionColor(rate).opacity(0.12))
            )
    }

    private func completionColor(_ rate: Int) -> Color {
        if rate >= 75 { return AppColors.completionGreen }
        if rate >= 40 { return AppColors.gold }
        return AppColors.coral
    }

    // MARK: - Bindings

    private func enabledBinding(for pref: CheckInPreference) -> Binding<Bool> {
        Binding(
            get: { pref.isEnabled },
            set: { newValue in
                pref.isEnabled = newValue
                rescheduleNotifications()
                refresh()
            }
        )
    }

    private func timeBinding(for pref: CheckInPreference) -> Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = pref.customHour
                components.minute = pref.customMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                pref.customHour = Calendar.current.component(.hour, from: newDate)
                pref.customMinute = Calendar.current.component(.minute, from: newDate)
                rescheduleNotifications()
            }
        )
    }

    private func timeRange(for checkInTime: CheckInTime) -> ClosedRange<Date> {
        let baseHour = checkInTime.hour
        let minHour = max(0, baseHour - 2)
        let maxHour = min(23, baseHour + 2)

        var minComponents = DateComponents()
        minComponents.hour = minHour
        minComponents.minute = 0

        var maxComponents = DateComponents()
        maxComponents.hour = maxHour
        maxComponents.minute = 59

        let calendar = Calendar.current
        let minDate = calendar.date(from: minComponents) ?? Date()
        let maxDate = calendar.date(from: maxComponents) ?? Date()
        return minDate...maxDate
    }

    // MARK: - Actions

    private func acceptSuggestion(_ suggestion: CheckInSuggestion) {
        behaviorEngine?.applySuggestion(suggestion)
        rescheduleNotifications()
        refresh()
    }

    private func dismissSuggestion(_ suggestion: CheckInSuggestion) {
        behaviorEngine?.dismissSuggestion(suggestion)
        refresh()
    }

    private func rescheduleNotifications() {
        guard let engine = behaviorEngine else { return }
        let activePrefs = engine.activePreferences()
        let notificationManager = NotificationManager()
        notificationManager.scheduleCheckInReminders(preferences: activePrefs)
        engine.syncWidgetData()
    }

    private func refresh() {
        preferences = behaviorEngine?.allPreferences() ?? []
        insights = behaviorEngine?.windowInsights ?? []
        activeSuggestion = behaviorEngine?.activeSuggestion
    }
}
