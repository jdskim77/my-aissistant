import SwiftUI

/// Coach settings — user-facing tuning for proactive nudges.
///
/// This screen is for *tuning* the coach (toggle / frequency / quiet
/// hours / silenceable categories), not for *consuming* its output.
/// The consumption surface — seeing what the coach said and reacting
/// to it — lives on the Coach tab as a pinned nudge above the
/// transcript. Conflating the two jobs here (which an earlier
/// iteration did with a "Recent nudges" section) buried the receipt
/// under 8 toggles where no user would find it.
///
/// Transparency is load-bearing here: the user must always be able to
/// see what the coach decides, why, and silence it. The "why" lives in
/// this view; the "what" lives on the Coach tab.
struct CoachSettingsView: View {

    @AppStorage(AppConstants.nudgeEnabledKey)
    private var nudgesEnabled: Bool = false

    @AppStorage(AppConstants.nudgeFrequencyKey)
    private var frequencyRaw: String = NudgeFrequency.balanced.rawValue

    @AppStorage(AppConstants.nudgeSilencedCategoriesKey)
    private var silencedCategoriesRaw: String = ""

    @AppStorage(AppConstants.nudgeQuietHoursStartKey)
    private var quietStartHour: Int = AppConstants.nudgeQuietHoursStartHour

    @AppStorage(AppConstants.nudgeQuietHoursEndKey)
    private var quietEndHour: Int = AppConstants.nudgeQuietHoursEndHour

    /// Opt-in for the post-check-in action-suggestion rule. Default OFF
    /// — mood-triggered nudges need explicit consent per the expert
    /// panel's guidance. Toggle label intentionally describes the
    /// behavior ("suggestions after check-ins"), not the mechanism
    /// ("PostLowMoodCheckInRule"). The Recent Nudges @Query that lived
    /// here on the Rule #2 branch was intentionally removed in the IA
    /// merge — the Coach tab's pinned-nudge card is now the canonical
    /// reaction surface.
    @AppStorage(AppConstants.nudgePostLowMoodEnabledKey)
    private var postLowMoodEnabled: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Proactive nudges", isOn: $nudgesEnabled)
                    .tint(AppColors.accent)

                if nudgesEnabled {
                    Picker("Frequency", selection: $frequencyRaw) {
                        Text("Gentle · 1/day").tag(NudgeFrequency.gentle.rawValue)
                        Text("Balanced · 2/day").tag(NudgeFrequency.balanced.rawValue)
                        Text("Off").tag(NudgeFrequency.off.rawValue)
                    }
                    .pickerStyle(.menu)

                    Toggle("Action suggestions after check-ins", isOn: $postLowMoodEnabled)
                        .tint(AppColors.accent)
                }
            } header: {
                Text("Coach")
            } footer: {
                if nudgesEnabled && postLowMoodEnabled {
                    Text("Specific, well-timed suggestions from your coach across body, mind, heart, and spirit. When you log a low mood, the coach may suggest a small concrete action — you can silence this any time.")
                } else {
                    Text("Specific, well-timed suggestions from your coach across body, mind, heart, and spirit. Always with consent; silenceable any time.")
                }
            }

            if nudgesEnabled {
                Section {
                    Stepper(
                        "Start · \(hourLabel(quietStartHour))",
                        value: $quietStartHour,
                        in: 0...23
                    )
                    Stepper(
                        "End · \(hourLabel(quietEndHour))",
                        value: $quietEndHour,
                        in: 0...23
                    )
                } header: {
                    Text("Quiet hours")
                } footer: {
                    Text("No nudges delivered during these hours. Nudges that would have fired in quiet hours are deferred or expired. Setting start and end to the same hour disables quiet hours entirely.")
                }

                Section {
                    // `.safetyRoute` is intentionally excluded from the
                    // silenceable list — safety-resource nudges fire only
                    // when the on-device crisis classifier flags, and must
                    // not be user-suppressible per `crisis-safety-protocols`.
                    ForEach(Self.silenceableCategories, id: \.rawValue) { category in
                        Toggle(
                            categoryLabel(category),
                            isOn: Binding(
                                get: { !isSilenced(category) },
                                set: { newValue in setSilenced(category, !newValue) }
                            )
                        )
                        .tint(AppColors.accent)
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Silence a category if it stops feeling useful — the coach will respect your choice. Safety resources are always available and can't be silenced here.")
                }

            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        let normalized = max(0, min(23, hour))
        var comps = DateComponents()
        comps.hour = normalized
        let date = Calendar.current.date(from: comps) ?? Date()
        return Self.hourFormatter.string(from: date)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        f.locale = Locale.current
        return f
    }()

    /// Categories the user is allowed to silence from this surface.
    /// `.safetyRoute` is excluded — crisis-triggered safety resources must
    /// remain reachable regardless of the user's silencing preferences.
    private static let silenceableCategories: [NudgeCategory] = NudgeCategory.allCases
        .filter { $0 != .safetyRoute }

    private func categoryLabel(_ category: NudgeCategory) -> String {
        switch category {
        case .weakDimension:     return "Weak-area nudges"
        case .streakAtRisk:      return "Streak at risk"
        case .calendarGap:       return "Calendar resets"
        case .habitSlip:         return "Habit slips"
        case .postCheckInAction: return "After a check-in"
        case .goalCheckpoint:    return "Goal checkpoints"
        case .safetyRoute:       return "Safety resources"  // not shown in UI; kept for exhaustiveness
        }
    }

    private func silencedCategories() -> Set<String> {
        guard !silencedCategoriesRaw.isEmpty else { return [] }
        return Set(silencedCategoriesRaw.split(separator: ",").map(String.init))
    }

    private func isSilenced(_ category: NudgeCategory) -> Bool {
        silencedCategories().contains(category.rawValue)
    }

    private func setSilenced(_ category: NudgeCategory, _ silenced: Bool) {
        var set = silencedCategories()
        if silenced {
            set.insert(category.rawValue)
        } else {
            set.remove(category.rawValue)
        }
        silencedCategoriesRaw = set.sorted().joined(separator: ",")
    }
}

#Preview {
    NavigationStack {
        CoachSettingsView()
    }
}
