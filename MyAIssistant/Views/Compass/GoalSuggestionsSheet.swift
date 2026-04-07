import SwiftUI
import SwiftData

/// On-demand AI task suggestions tied to the user's active Season Goal.
/// Presented as a sheet from SeasonGoalView via `.sheet(item:)`.
struct GoalSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.keychainService) private var keychainService
    @Environment(\.subscriptionTier) private var subscriptionTier
    @Environment(\.usageGateManager) private var usageGateManager
    @Environment(\.taskManager) private var taskManager
    @Environment(\.subscriptionManager) private var subscriptionManager

    let goal: SeasonGoal

    @State private var suggestions: [GoalTaskSuggestion] = []
    @State private var addedSuggestionIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isGated = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    content
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 32)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Suggest Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        Haptics.light()
                        dismiss()
                    }
                    .accessibilityLabel("Close suggestions")
                }
            }
            .task { await loadIfNeeded() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: goal.dimension.icon)
                .font(AppFonts.display(32).weight(.medium))
                .foregroundColor(goal.dimension.color)
                .frame(width: 64, height: 64)
                .background(goal.dimension.color.opacity(0.1))
                .cornerRadius(16)

            VStack(spacing: 4) {
                Text("Goal: \(goal.intention.isEmpty ? goal.dimension.label : goal.intention)")
                    .font(AppFonts.heading(17))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(goal.daysRemaining) days left")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isGated {
            gatedView
        } else if isLoading {
            loadingView
        } else if let errorMessage {
            errorView(message: errorMessage)
        } else if suggestions.isEmpty {
            errorView(message: "No suggestions returned. Try again.")
        } else {
            suggestionsList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                LoadingView(lines: 3)
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(AppFonts.display(28))
                .foregroundColor(AppColors.coral)
            Text(message)
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Haptics.light()
                Task { await retry() }
            } label: {
                Text("Retry")
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppColors.accent)
                    .cornerRadius(12)
            }
            .accessibilityLabel("Retry fetching suggestions")
        }
        .padding(20)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var gatedView: some View {
        PaywallCard(
            title: "Out of suggestions this week",
            message: "Free plan includes \(AppConstants.freeGoalSuggestionsPerWeek) AI goal suggestions per week. Upgrade for unlimited.",
            action: nil
        )
    }

    private var suggestionsList: some View {
        VStack(spacing: 14) {
            ForEach(suggestions) { suggestion in
                suggestionCard(suggestion)
            }

            if !suggestions.isEmpty && addedSuggestionIDs.count < suggestions.count {
                Button {
                    Haptics.success()
                    addAll()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add all")
                    }
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(goal.dimension.color)
                    .cornerRadius(14)
                }
                .accessibilityLabel("Add all remaining suggestions")
            }
        }
    }

    // MARK: - Suggestion Card

    private func suggestionCard(_ suggestion: GoalTaskSuggestion) -> some View {
        let isAdded = addedSuggestionIDs.contains(suggestion.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(suggestion.icon)
                    .font(AppFonts.display(24))
                    .frame(width: 44, height: 44)
                    .background(goal.dimension.color.opacity(0.08))
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        categoryTag(suggestion.category)
                        Text("\(suggestion.durationMinutes) min")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                        Text(suggestion.priority.shortLabel)
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                    }
                }

                Spacer(minLength: 0)
            }

            if !suggestion.rationale.isEmpty {
                Text(suggestion.rationale)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.success()
                add(suggestion)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    Text(isAdded ? "Added" : "Add")
                }
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(isAdded ? AppColors.completionGreen : AppColors.onAccent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isAdded ? AppColors.completionGreen.opacity(0.12) : goal.dimension.color)
                .cornerRadius(12)
            }
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? "Already added: \(suggestion.title)" : "Add task: \(suggestion.title)")
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private func categoryTag(_ category: TaskCategory) -> some View {
        HStack(spacing: 4) {
            Text(category.icon)
                .font(AppFonts.caption(11))
            Text(category.rawValue)
                .font(AppFonts.caption(11))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(AppColors.surface)
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard suggestions.isEmpty, !isGated else { return }

        // Gate check first.
        if let gate = usageGateManager, !gate.canSuggestGoalTasks(tier: subscriptionTier) {
            isGated = true
            isLoading = false
            return
        }

        await fetch()
    }

    private func retry() async {
        errorMessage = nil
        isLoading = true
        await fetch()
    }

    private func fetch() async {
        let suggester = GoalTaskSuggester(keychain: keychainService, tier: subscriptionTier)
        let recent = recentTaskTitles()
        let schedule = taskManager?.scheduleSummary() ?? ""

        do {
            let result = try await suggester.suggestTasks(
                for: goal,
                recentTaskTitles: recent,
                scheduleSummary: schedule
            )
            await MainActor.run {
                self.suggestions = result
                self.isLoading = false
                self.errorMessage = nil
                usageGateManager?.recordGoalSuggestion()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func recentTaskTitles() -> [String] {
        let now = Date()
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.date >= fourteenDaysAgo },
            sortBy: [SortDescriptor(\TaskItem.date, order: .reverse)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.prefix(30).map { $0.title }
    }

    private func add(_ suggestion: GoalTaskSuggestion) {
        guard !addedSuggestionIDs.contains(suggestion.id) else { return }

        let scheduledDate = nextAvailableSlot()
        let task = TaskItem(
            title: suggestion.title,
            category: suggestion.category,
            priority: suggestion.priority,
            date: scheduledDate,
            done: false,
            icon: suggestion.icon,
            notes: suggestion.rationale
        )
        // Tie the task to the goal's dimension so it feeds into balance tracking.
        task.dimension = goal.dimension

        modelContext.insert(task)
        modelContext.safeSave()
        addedSuggestionIDs.insert(suggestion.id)
    }

    private func addAll() {
        for suggestion in suggestions where !addedSuggestionIDs.contains(suggestion.id) {
            add(suggestion)
        }
    }

    /// Finds a sensible default slot: tomorrow 9 AM if it's late today, otherwise
    /// the next round hour at least 2 hours from now.
    private func nextAvailableSlot() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        if hour > 18 {
            // Tomorrow 9 AM
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        } else {
            let targetHour = min(22, hour + 2)
            return calendar.date(bySettingHour: targetHour, minute: 0, second: 0, of: now) ?? now
        }
    }
}
