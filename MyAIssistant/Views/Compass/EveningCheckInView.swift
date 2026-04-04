import SwiftUI

/// The evening check-in flow:
///   Step 1: Rate satisfaction per dimension (1-5 each) — feeds 40% of Compass score
///   Step 2: Energy slider (-3 to +3)
///   Step 3: Smart Activity Recall (if patterns detected)
///   Step 4: Confirmation + auto-dismiss
struct EveningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    let balanceManager: BalanceManager

    @State private var step: CheckInStep = .satisfaction
    @State private var ratings: [LifeDimension: Int] = [:]
    @State private var energyRating: Double = 0
    @State private var processing = false
    @State private var recallSuggestions: [BalanceManager.RecallSuggestion] = []
    @State private var selectedDuration: [String: Int] = [:]

    private enum CheckInStep {
        case satisfaction, energy, recall, confirmation
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                switch step {
                case .satisfaction:
                    satisfactionStep
                case .energy:
                    energySliderStep
                case .recall:
                    recallStep
                case .confirmation:
                    confirmationState
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            balanceManager.updateActivityPatterns()
            recallSuggestions = balanceManager.recallSuggestions()
            // Pre-fill with today's existing ratings if any
            let existing = balanceManager.todaySatisfaction()
            if !existing.isEmpty {
                ratings = existing
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: headerIcon)
                .font(AppFonts.icon(36))
                .foregroundColor(headerColor)

            Text(headerTitle)
                .font(AppFonts.heading(20))
                .foregroundColor(AppColors.textPrimary)

            Text(headerSubtitle)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var headerIcon: String {
        switch step {
        case .satisfaction: return "moon.stars.fill"
        case .energy: return "battery.100.bolt"
        case .recall: return "brain.head.profile"
        case .confirmation: return "checkmark.circle.fill"
        }
    }

    private var headerColor: Color {
        switch step {
        case .satisfaction: return AppColors.night
        case .energy: return AppColors.gold
        case .recall: return AppColors.accent
        case .confirmation: return AppColors.completionGreen
        }
    }

    private var headerTitle: String {
        switch step {
        case .satisfaction: return "Evening Check-in"
        case .energy: return "Energy Check"
        case .recall: return "Anything Else?"
        case .confirmation: return "All Set"
        }
    }

    private var headerSubtitle: String {
        switch step {
        case .satisfaction: return "How did each area feel today?"
        case .energy: return "How did today feel overall?"
        case .recall: return "I noticed a few things you might have done today"
        case .confirmation: return "This helps build your weekly Compass"
        }
    }

    // MARK: - Step 1: Per-Dimension Satisfaction Ratings

    private var satisfactionStep: some View {
        VStack(spacing: 16) {
            ForEach(LifeDimension.scored) { dim in
                satisfactionRow(dim)
            }

            // Continue button
            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.35)) {
                    step = .energy
                }
            } label: {
                Text(ratings.isEmpty ? "Skip ratings" : "Continue")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(ratings.isEmpty ? AppColors.textMuted : AppColors.accent)
                    .cornerRadius(14)
            }
            .accessibilityLabel(ratings.isEmpty ? "Skip satisfaction ratings" : "Continue to energy check")

            Button {
                Haptics.light()
                dismiss()
            } label: {
                Text("Skip for today")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Skip evening check-in")
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func satisfactionRow(_ dim: LifeDimension) -> some View {
        HStack(spacing: 12) {
            // Dimension icon + name
            HStack(spacing: 8) {
                Image(systemName: dim.icon)
                    .font(AppFonts.heading(18).weight(.medium))
                    .foregroundColor(dim.color)
                    .frame(width: 28)

                Text(dim.label)
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(AppColors.textPrimary)
            }
            .frame(width: 110, alignment: .leading)

            // 1-5 rating dots
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.15)) {
                            if ratings[dim] == value {
                                ratings.removeValue(forKey: dim) // tap again to deselect
                            } else {
                                ratings[dim] = value
                            }
                        }
                    } label: {
                        let isSelected = (ratings[dim] ?? 0) >= value
                        Circle()
                            .fill(isSelected ? dim.color : dim.color.opacity(0.15))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text("\(value)")
                                    .font(AppFonts.label(12))
                                    .foregroundColor(isSelected ? AppColors.onAccent : dim.color)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(dim.label) rating \(value) of 5")
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Step 2: Energy Slider

    private var energySliderStep: some View {
        VStack(spacing: 24) {
            Text(energyEmoji)
                .font(AppFonts.icon(48))
                .animation(.snappy(duration: 0.15), value: energyEmoji)

            VStack(spacing: 8) {
                Slider(value: $energyRating, in: -3...3, step: 1) {
                    Text("Energy")
                } minimumValueLabel: {
                    Text("Drained")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.coral)
                } maximumValueLabel: {
                    Text("Energized")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.completionGreen)
                }
                .tint(energySliderColor)

                Text(energyLabel)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 8)

            Button {
                Haptics.success()
                saveCheckIn()
                advanceFromEnergy()
            } label: {
                Text("Save")
                    .font(AppFonts.bodyMedium(16))
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accent)
                    .cornerRadius(16)
            }
            .accessibilityLabel("Save check-in")

            Button {
                Haptics.light()
                saveCheckIn()
                advanceFromEnergy()
            } label: {
                Text("Skip energy rating")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .frame(minHeight: 44)
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func advanceFromEnergy() {
        withAnimation(.spring(response: 0.35)) {
            if !recallSuggestions.isEmpty {
                step = .recall
            } else {
                step = .confirmation
            }
        }
    }

    // MARK: - Step 3: Smart Activity Recall

    private var recallStep: some View {
        VStack(spacing: 16) {
            ForEach(recallSuggestions) { suggestion in
                recallCard(suggestion)
            }

            Button {
                Haptics.light()
                for suggestion in recallSuggestions {
                    balanceManager.dismissRecall(suggestion.pattern)
                }
                withAnimation(.spring(response: 0.35)) {
                    step = .confirmation
                }
            } label: {
                Text("Skip all")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textMuted)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Skip activity recall")
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    private func recallCard(_ suggestion: BalanceManager.RecallSuggestion) -> some View {
        let pattern = suggestion.pattern
        let duration = selectedDuration[pattern.id] ?? pattern.typicalDurationMinutes

        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: pattern.dimension.icon)
                    .font(AppFonts.heading(20).weight(.medium))
                    .foregroundColor(pattern.dimension.color)

                Text(suggestion.message)
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { mins in
                    Button {
                        Haptics.selection()
                        selectedDuration[pattern.id] = mins
                    } label: {
                        Text("\(mins)m")
                            .font(AppFonts.label(12))
                            .foregroundColor(duration == mins ? AppColors.onAccent : pattern.dimension.color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .background(duration == mins ? pattern.dimension.color : pattern.dimension.color.opacity(0.1))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Haptics.success()
                    balanceManager.acceptRecall(pattern, durationMinutes: duration)
                    withAnimation(.spring(response: 0.3)) {
                        recallSuggestions.removeAll { $0.id == suggestion.id }
                    }
                    if recallSuggestions.isEmpty {
                        withAnimation(.spring(response: 0.35)) { step = .confirmation }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(AppFonts.label(13))
                        Text("Yes, \(duration) min")
                            .font(AppFonts.bodyMedium(14))
                    }
                    .foregroundColor(AppColors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(pattern.dimension.color)
                    .cornerRadius(10)
                }

                Button {
                    Haptics.light()
                    balanceManager.dismissRecall(pattern)
                    withAnimation(.spring(response: 0.3)) {
                        recallSuggestions.removeAll { $0.id == suggestion.id }
                    }
                    if recallSuggestions.isEmpty {
                        withAnimation(.spring(response: 0.35)) { step = .confirmation }
                    }
                } label: {
                    Text("Not today")
                        .font(AppFonts.body(14))
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(pattern.dimension.color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Step 4: Confirmation

    private var confirmationState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppFonts.icon(48))
                .foregroundColor(AppColors.completionGreen)

            Text("All Set")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)

            // Show what was saved
            if !ratings.isEmpty {
                let ratedCount = ratings.count
                Text("\(ratedCount) dimension\(ratedCount == 1 ? "" : "s") rated")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
            }

            if Int(energyRating) != 0 {
                Text("Energy: \(energyLabel)")
                    .font(AppFonts.body(14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Text("This helps build your weekly Compass")
                .font(AppFonts.caption(14))
                .foregroundColor(AppColors.textMuted)
        }
        .transition(.scale.combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }

    // MARK: - Save

    private func saveCheckIn() {
        let energy = Int(energyRating)
        if !ratings.isEmpty {
            // Use the new multi-dimension satisfaction method
            balanceManager.recordSatisfaction(
                ratings: ratings,
                energyRating: energy == 0 ? nil : energy
            )
        } else {
            // No ratings — just save energy via legacy method with best guess dimension
            let bestDim = LifeDimension.scored.first ?? .physical
            balanceManager.recordCheckIn(dimension: bestDim, energyRating: energy == 0 ? nil : energy)
        }
    }

    // MARK: - Helpers

    private var energyEmoji: String {
        switch Int(energyRating) {
        case -3: return "😩"
        case -2: return "😔"
        case -1: return "😐"
        case 0:  return "🙂"
        case 1:  return "😊"
        case 2:  return "😄"
        case 3:  return "🔥"
        default: return "🙂"
        }
    }

    private var energyLabel: String {
        switch Int(energyRating) {
        case -3: return "Completely drained"
        case -2: return "Pretty tired"
        case -1: return "Slightly low"
        case 0:  return "Neutral"
        case 1:  return "Pretty good"
        case 2:  return "Feeling great"
        case 3:  return "On fire"
        default: return "Neutral"
        }
    }

    private var energySliderColor: Color {
        let rating = Int(energyRating)
        if rating <= -2 { return AppColors.coral }
        if rating <= 0 { return AppColors.gold }
        return AppColors.completionGreen
    }
}
