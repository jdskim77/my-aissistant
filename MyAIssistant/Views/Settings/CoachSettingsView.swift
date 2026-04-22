import SwiftUI
import SwiftData

/// Coach settings — user-facing tuning for proactive nudges.
///
/// Phase 1 shipped the toggles; Phase 2 Part C adds the **Recent nudges**
/// receipt drawer so the user can see what the coach has been doing and
/// react to it. Every reaction feeds back into the dogfood hit-rate metric
/// that gates adding further trigger rules.
///
/// Transparency is load-bearing here: the user must always be able to see
/// what the coach decides, why, and silence it.
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
    /// ("PostLowMoodCheckInRule").
    @AppStorage(AppConstants.nudgePostLowMoodEnabledKey)
    private var postLowMoodEnabled: Bool = false

    /// All nudges sorted most-recent first. Filtering for delivered/responded
    /// status happens in `recentNudges` below.
    ///
    /// The `@Query` predicate was originally a `#Predicate<Nudge>` against
    /// `statusRaw`, but the combination of the or-clause + the sort descriptor
    /// tripped Swift's type-check budget ("compiler unable to type-check this
    /// expression in reasonable time"), which in turn made the synthesized
    /// initializer incompatible with the `#Preview`. Simpler @Query + in-Swift
    /// filter keeps the view compileable at zero cost — there are at most a
    /// few dozen Nudge rows ever, so filtering in-memory is trivial.
    @Query(sort: [SortDescriptor(\Nudge.createdAt, order: .reverse)])
    private var allNudges: [Nudge]

    @Environment(\.nudgeEngine) private var nudgeEngine: NudgeEngine?

    private var recentNudges: [Nudge] {
        Array(
            allNudges
                .filter { $0.statusRaw == "delivered" || $0.statusRaw == "responded" }
                .prefix(5)
        )
    }

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

                Section {
                    if recentNudges.isEmpty {
                        Text("No nudges yet. Check back after a few days of use — the coach needs a week of signal before it starts reaching out.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(recentNudges) { nudge in
                            RecentNudgeRow(nudge: nudge) { response in
                                nudgeEngine?.recordResponse(nudgeID: nudge.id, response: response)
                            }
                        }
                    }
                } header: {
                    Text("Recent from your coach")
                } footer: {
                    Text("Last 5 nudges delivered. Your reactions help the coach tune future ones — this is the dogfood signal that gates new rule types.")
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

// MARK: - Recent nudge row

/// One row in the "Recent from your coach" list. Renders the nudge body,
/// category, relative timestamp, and either a thumbs-up/down reaction pair
/// (unresponded) or a past-tense summary of the prior reaction.
///
/// Safety-route nudges render with an amber tint and a "Get support" link
/// instead of reaction buttons — asking "was that helpful?" after a
/// safety intervention is tone-deaf. Tapping the link opens the
/// `SafeResourceCopy.actionURL` in the system browser.
private struct RecentNudgeRow: View {
    let nudge: Nudge
    let onReact: (UserNudgeResponse) -> Void

    private var isSafety: Bool { nudge.category == .safetyRoute }

    private var existingResponse: UserNudgeResponse? {
        guard let raw = nudge.userResponseRaw else { return nil }
        return UserNudgeResponse(rawValue: raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(categoryBadge(nudge.category))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(isSafety ? Color.orange : AppColors.accent)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(nudge.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            Text(nudge.bodyText)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if isSafety {
                Link(destination: SafeResourceCopy.actionURL()) {
                    Label(SafeResourceCopy.actionTitle, systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .foregroundStyle(Color.orange)
            } else if let response = existingResponse {
                HStack(spacing: 6) {
                    Image(systemName: responseIcon(response))
                        .font(.caption)
                    Text(responseSummary(response))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button {
                        onReact(.accepted)
                    } label: {
                        Label("Helpful", systemImage: "hand.thumbsup")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.accent)

                    Button {
                        onReact(.dismissed)
                    } label: {
                        Label("Not helpful", systemImage: "hand.thumbsdown")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Formatting

    private func categoryBadge(_ category: NudgeCategory) -> String {
        switch category {
        case .weakDimension:     return "WEAK AREA"
        case .streakAtRisk:      return "STREAK"
        case .calendarGap:       return "RESET"
        case .habitSlip:         return "HABIT"
        case .postCheckInAction: return "CHECK-IN"
        case .goalCheckpoint:    return "GOAL"
        case .safetyRoute:       return "SUPPORT"
        }
    }

    private func responseSummary(_ response: UserNudgeResponse) -> String {
        switch response {
        case .accepted:  return "You found this helpful"
        case .dismissed: return "You didn't find this helpful"
        case .snoozed:   return "Snoozed"
        case .ignored:   return "No response"
        case .silenced:  return "Silenced"
        }
    }

    private func responseIcon(_ response: UserNudgeResponse) -> String {
        switch response {
        case .accepted:  return "hand.thumbsup.fill"
        case .dismissed: return "hand.thumbsdown.fill"
        case .snoozed:   return "clock"
        case .ignored:   return "questionmark.circle"
        case .silenced:  return "speaker.slash"
        }
    }
}

#Preview {
    NavigationStack {
        CoachSettingsView()
    }
}
