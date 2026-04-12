import SwiftUI

/// Reusable dimension chip picker supporting multi-select (max 3).
/// Used in task creation/editing flows.
///
/// Modes:
///   - No suggestion: all chips neutral
///   - Keyword/category suggestions: sparkle chip(s) above row, nothing pre-selected
///   - Learned preference: chip(s) pre-selected (filled)
struct DimensionPickerView: View {
    @Binding var selection: Set<LifeDimension>
    var suggestions: [DimensionSuggester.Suggestion]
    var showPractical: Bool = true
    var maxSelections: Int = 3

    private var dimensions: [LifeDimension] {
        showPractical ? LifeDimension.allCases : LifeDimension.scored
    }

    /// True if the top suggestion is high-confidence (learned from user behavior)
    private var hasLearnedSuggestion: Bool {
        suggestions.first?.confidence == .learned
    }

    /// Suggestions that are keyword/category (not learned), not yet selected, and room left
    private var pendingSuggestions: [DimensionSuggester.Suggestion] {
        guard selection.count < maxSelections else { return [] }
        return suggestions.filter { $0.confidence != .learned && !selection.contains($0.dimension) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Life Dimensions")
                    .font(AppFonts.heading(14))
                    .foregroundColor(AppColors.textSecondary)

                if selection.count > 0 {
                    Text("\(selection.count)/\(maxSelections)")
                        .font(AppFonts.caption(11))
                        .foregroundColor(AppColors.textMuted)
                }

                // Show sparkle chips for keyword/category suggestions not yet selected
                ForEach(pendingSuggestions, id: \.dimension) { suggestion in
                    Button {
                        Haptics.light()
                        addDimension(suggestion.dimension)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(AppFonts.caption(11))
                            Text(suggestion.dimension.label)
                                .font(AppFonts.label(11))
                        }
                        .foregroundColor(suggestion.dimension.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(suggestion.dimension.color.opacity(0.12))
                        .cornerRadius(6)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suggested: \(suggestion.dimension.label)")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(dimensions) { dim in
                        dimensionChip(dim)
                    }
                }
            }
        }
        .onAppear {
            // Auto-select learned preferences (high confidence)
            if selection.isEmpty {
                for suggestion in suggestions where suggestion.confidence == .learned {
                    addDimension(suggestion.dimension)
                }
            }
        }
    }

    private func addDimension(_ dim: LifeDimension) {
        guard selection.count < maxSelections else { return }
        withAnimation(.snappy(duration: 0.2)) {
            selection.insert(dim)
        }
    }

    private func dimensionChip(_ dim: LifeDimension) -> some View {
        let isSelected = selection.contains(dim)
        let isLearned = hasLearnedSuggestion && suggestions.contains(where: { $0.dimension == dim && $0.confidence == .learned }) && isSelected

        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) {
                if isSelected {
                    selection.remove(dim)
                } else if selection.count < maxSelections {
                    selection.insert(dim)
                }
            }
        } label: {
            HStack(spacing: 5) {
                if isLearned {
                    Image(systemName: "sparkles")
                        .font(AppFonts.caption(11))
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Image(systemName: dim.icon)
                    .font(AppFonts.label(12))
                Text(dim.label)
                    .font(AppFonts.bodyMedium(13))
            }
            .foregroundColor(isSelected ? .white : dim.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(isSelected ? dim.color : dim.color.opacity(0.1))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : dim.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dim.label)\(isSelected ? ", selected" : "")\(isLearned ? ", learned preference" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(selection.count >= maxSelections && !isSelected ? 0.4 : 1.0)
    }
}
