import SwiftUI

struct OnboardingSuggestedTasksView: View {
    let tasks: [StarterTask]
    @Binding var addedIndices: Set<Int>
    let weakestDimension: LifeDimension
    let onContinue: () -> Void
    @State private var appeared = false

    private var dimensionLabel: String {
        switch weakestDimension {
        case .physical:  return "your body"
        case .mental:    return "your mind"
        case .emotional: return "your connections"
        case .spiritual: return "your contribution"
        case .practical: return "your routines"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: weakestDimension.icon)
                        .font(AppFonts.icon(36))
                        .foregroundColor(weakestDimension.color)

                    Text("Let's strengthen \(dimensionLabel)")
                        .font(AppFonts.display(22))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Here are 3 small things to try this week:")
                        .font(AppFonts.body(15))
                        .foregroundColor(AppColors.textSecondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 15)

                // Task cards
                VStack(spacing: 12) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        taskCard(task: task, index: index)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : CGFloat(20 + index * 8))
                            .animation(
                                .easeOut(duration: 0.4).delay(Double(index) * 0.1),
                                value: appeared
                            )
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text(addedIndices.isEmpty ? "Skip for Now" : "Continue")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(addedIndices.isEmpty ? AppColors.textSecondary : AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(addedIndices.isEmpty ? AppColors.surface : AppColors.accent)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(addedIndices.isEmpty ? AppColors.border : Color.clear, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    // MARK: - Task Card

    private func taskCard(task: StarterTask, index: Int) -> some View {
        let isAdded = addedIndices.contains(index)

        return HStack(alignment: .top, spacing: 14) {
            Text(task.icon)
                .font(AppFonts.icon(28))
                .frame(width: 44, height: 44)
                .background(weakestDimension.color.opacity(0.08))
                .cornerRadius(10)

            Text(task.title)
                .font(AppFonts.body(15))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Haptics.light()
                withAnimation(.spring(response: 0.25)) {
                    if isAdded {
                        addedIndices.remove(index)
                    } else {
                        addedIndices.insert(index)
                    }
                }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(AppFonts.body(24))
                    .foregroundColor(isAdded ? AppColors.completionGreen : weakestDimension.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "Remove \(task.title)" : "Add \(task.title)")
        }
        .padding(14)
        .background(isAdded ? weakestDimension.color.opacity(0.06) : AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isAdded ? weakestDimension.color.opacity(0.2) : AppColors.border, lineWidth: 1)
        )
    }
}
