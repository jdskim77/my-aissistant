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
                .accessibilityLabel("Cancel task creation")

                ForEach(chips) { chip in
                    let isDimensionStep = step == .dimension
                    let isDimensionChip = isDimensionStep && chip.value != "done"
                    let isSelected = isDimensionChip && LifeDimension(rawValue: chip.value).map { selectedDimensions.contains($0) } ?? false
                    let isDoneChip = isDimensionStep && chip.value == "done"
                    let atMax = isDimensionStep && selectedDimensions.count >= 3

                    Button {
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
                        .foregroundColor(isDoneChip ? .white : isSelected ? .white : AppColors.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            isDoneChip ? AppColors.accent :
                            isSelected ? (LifeDimension(rawValue: chip.value)?.color ?? AppColors.accent) :
                            AppColors.accentLight
                        )
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .opacity(atMax && isDimensionChip && !isSelected ? 0.4 : 1.0)
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
