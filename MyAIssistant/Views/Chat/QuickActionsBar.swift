import SwiftUI

struct QuickActionsBar: View {
    let actions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        Text(action)
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColors.accentLight)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Task Builder Chips Bar

struct TaskBuilderChipsBar: View {
    let chips: [TaskBuilderChip]
    let step: TaskBuilderStep
    let selectedDimensions: Set<LifeDimension>
    let onSelect: (TaskBuilderChip) -> Void
    let onCancel: () -> Void

    // Done chip reused across renders so we don't allocate a fresh UUID per
    // body eval (BUG-09 from the Skip/Done QA pass — latent identity churn).
    private static let doneChip = TaskBuilderChip(label: "Done", icon: nil, value: "done")

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Cancel button
                Button {
                    Haptics.light()
                    onCancel()
                } label: {
                    Text("✕ Cancel")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.border.opacity(0.3))
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Cancel task creation")

                // On the dimension step, always offer an escape: "Skip" when
                // nothing is selected (not every task maps to a life dimension),
                // "Done" once the user has picked at least one. Both states
                // use the same accent-filled treatment so the button always
                // reads as an action — the prior "textMuted" Skip styling
                // looked like disabled chrome and blurred into the Cancel pill
                // (fixed BUG-02 from the Skip/Done QA pass).
                if step == .dimension {
                    let hasSelection = !selectedDimensions.isEmpty
                    Button {
                        Haptics.light()
                        onSelect(Self.doneChip)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasSelection ? "checkmark" : "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(hasSelection ? "Done" : "Skip")
                                .font(AppFonts.bodyMedium(13))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.accent)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(hasSelection ? "Done selecting dimensions" : "Skip dimension selection")
                }

                ForEach(chips) { chip in
                    let isDimensionStep = step == .dimension
                    let isSelected = isDimensionStep && LifeDimension(rawValue: chip.value).map { selectedDimensions.contains($0) } ?? false
                    let atMax = isDimensionStep && selectedDimensions.count >= 3

                    Button {
                        // BUG-03 fix: at the 3-dimension cap, tapping a new
                        // chip used to silently reject (no state change, but
                        // Haptics.light fired — felt broken). Now fire a
                        // warning haptic and swallow the tap; the 0.4 opacity
                        // already signals the cap visually.
                        if atMax && !isSelected {
                            Haptics.warning()
                            return
                        }
                        Haptics.light()
                        onSelect(chip)
                    } label: {
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            if let icon = chip.icon {
                                Text(icon)
                                    .font(AppFonts.body(13))
                            }
                            Text(chip.label)
                                .font(AppFonts.bodyMedium(13))
                        }
                        .foregroundColor(isSelected ? .white : AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? (LifeDimension(rawValue: chip.value)?.color ?? AppColors.accent) :
                            AppColors.accentLight
                        )
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .opacity(atMax && !isSelected ? 0.4 : 1.0)
                    .accessibilityLabel(
                        [chip.icon, chip.label].compactMap { $0 }.joined(separator: " ")
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}
