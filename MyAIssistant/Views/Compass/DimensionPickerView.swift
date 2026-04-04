import SwiftUI

/// Reusable single-row dimension chip picker. Used in task creation/editing flows.
/// Supports three modes:
///   - No suggestion: all chips neutral
///   - Keyword/category suggestion: sparkle chip above row, nothing pre-selected
///   - Learned preference: chip pre-selected (filled), sparkle inside chip
struct DimensionPickerView: View {
    @Binding var selection: LifeDimension?
    var suggestion: DimensionSuggester.Suggestion?
    var showPractical: Bool = true

    private var dimensions: [LifeDimension] {
        showPractical ? LifeDimension.allCases : LifeDimension.scored
    }

    /// True if the suggestion is high-confidence (learned from user behavior)
    private var isLearnedSuggestion: Bool {
        suggestion?.confidence == .learned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Life Dimension")
                    .font(AppFonts.heading(14))
                    .foregroundColor(AppColors.textSecondary)

                // Show sparkle chip only for low-confidence suggestions (keyword/category)
                if let suggestion, !isLearnedSuggestion, selection == nil {
                    Button {
                        Haptics.light()
                        selection = suggestion.dimension
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
                    .accessibilityLabel("Suggested dimension: \(suggestion.dimension.label)")
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
            if isLearnedSuggestion, selection == nil, let dim = suggestion?.dimension {
                selection = dim
            }
        }
    }

    private func dimensionChip(_ dim: LifeDimension) -> some View {
        let isSelected = selection == dim
        let isLearned = isLearnedSuggestion && dim == suggestion?.dimension && isSelected

        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) {
                selection = isSelected ? nil : dim
            }
        } label: {
            HStack(spacing: 5) {
                if isLearned {
                    Image(systemName: "sparkles")
                        .font(AppFonts.caption(11))
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
        .accessibilityLabel("\(dim.label)\(isLearned ? ", learned preference" : "")")
    }
}
