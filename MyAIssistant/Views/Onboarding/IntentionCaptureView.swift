import SwiftUI

struct IntentionCaptureView: View {
    let weakestDimension: LifeDimension
    @Binding var intention: String
    @Binding var goalDimension: LifeDimension
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var didInitDimension = false
    @FocusState private var isFocused: Bool

    private var trimmedIntention: String {
        intention.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedIntention.isEmpty
    }

    private var placeholder: String {
        switch goalDimension {
        case .physical:  return "e.g., Get back to running 3x/week"
        case .mental:    return "e.g., Read 20 minutes before bed"
        case .emotional: return "e.g., Have one real conversation each day"
        case .spiritual: return "e.g., 5 minutes of quiet every morning"
        case .practical: return "e.g., Spend 30 minutes on overdue admin"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "target")
                        .font(AppFonts.icon(64))
                        .foregroundColor(AppColors.accent)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .padding(.top, 20)

                    VStack(spacing: 12) {
                        Text("What matters most right now?")
                            .font(AppFonts.display(28))
                            .foregroundColor(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Pick one area to focus on this month. I'll help you make progress.")
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Dimension chips (2x2 grid)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(LifeDimension.scored) { dim in
                            dimensionChip(dim)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Intention text field
                    VStack(spacing: 6) {
                        TextField(placeholder, text: $intention, axis: .vertical)
                            .font(AppFonts.body(16))
                            .foregroundColor(AppColors.textPrimary)
                            .lineLimit(2...4)
                            .focused($isFocused)
                            .submitLabel(.done)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { isFocused = false }
                                        .font(AppFonts.bodyMedium(15))
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(AppColors.card)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isFocused ? goalDimension.color : AppColors.border, lineWidth: 1)
                            )
                            .accessibilityLabel("Your intention")
                            .onChange(of: intention) { _, newValue in
                                if newValue.count > 200 {
                                    intention = String(newValue.prefix(200))
                                }
                            }

                        Text("One sentence is enough. You can change this later.")
                            .font(AppFonts.caption(12))
                            .foregroundColor(AppColors.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 12) {
                Divider()

                Button(action: {
                    Haptics.light()
                    onContinue()
                }) {
                    Text("Set My Focus")
                        .font(AppFonts.bodyMedium(17))
                        .foregroundColor(AppColors.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isValid ? goalDimension.color : AppColors.accent.opacity(0.4))
                        .cornerRadius(14)
                }
                .disabled(!isValid)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .accessibilityHint("Saves your focus and continues")

                Button(action: {
                    Haptics.selection()
                    onSkip()
                }) {
                    Text("Maybe later")
                        .font(AppFonts.bodyMedium(15))
                        .foregroundColor(AppColors.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.bottom, 40)
                .accessibilityHint("Skips this step and continues")
            }
            .background(AppColors.surface)
        }
        .background(AppColors.background.ignoresSafeArea())
        .onAppear {
            if !didInitDimension {
                goalDimension = weakestDimension
                didInitDimension = true
            }
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    private func dimensionChip(_ dim: LifeDimension) -> some View {
        let isSelected = goalDimension == dim
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                goalDimension = dim
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: dim.icon)
                    .font(AppFonts.bodyMedium(18))
                    .foregroundColor(isSelected ? .white : dim.color)
                Text(dim.label)
                    .font(AppFonts.bodyMedium(14))
                    .foregroundColor(isSelected ? .white : AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? dim.color : AppColors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dim.label) dimension, \(isSelected ? "selected" : "tap to select")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
