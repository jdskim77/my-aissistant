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

                // Show "Done" right after Cancel when dimensions are selected — most tasks need just 1
                if step == .dimension && !selectedDimensions.isEmpty {
                    let doneChip = TaskBuilderChip(label: "Done", icon: nil, value: "done")
                    Button {
                        Haptics.light()
                        onSelect(doneChip)
                    } label: {
                        Text("Done")
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColors.accent)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done selecting dimensions")
                }

                ForEach(chips) { chip in
                    let isDimensionStep = step == .dimension
                    let isSelected = isDimensionStep && LifeDimension(rawValue: chip.value).map { selectedDimensions.contains($0) } ?? false
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
