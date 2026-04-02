import SwiftUI
import SwiftData

struct HabitFormView: View {
    enum Mode: Identifiable {
        case create
        case edit(HabitItem)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let h): return h.id
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let mode: Mode

    @State private var title: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var frequency: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var showDeleteConfirm = false

    private let colorOptions = ["#2D5016", "#1A5276", "#B8860B", "#C94B2B", "#5856D6", "#34C759", "#FF9500", "#007AFF"]
    private let iconOptions = ["💪", "📚", "🏃", "💧", "🧘", "✍️", "🎯", "💤", "🥗", "🎸", "📝", "🧹"]
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingHabit: HabitItem? {
        if case .edit(let h) = mode { return h }
        return nil
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _icon = State(initialValue: "💪")
            _colorHex = State(initialValue: "#2D5016")
            _frequency = State(initialValue: .daily)
            _selectedDays = State(initialValue: Set(1...7))
        case .edit(let habit):
            _title = State(initialValue: habit.title)
            _icon = State(initialValue: habit.icon)
            _colorHex = State(initialValue: habit.colorHex)
            _frequency = State(initialValue: habit.targetDays)
            if case .specificDays(let days) = habit.targetDays {
                _selectedDays = State(initialValue: days)
            } else {
                _selectedDays = State(initialValue: Set(1...7))
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Icon picker
                    VStack(spacing: 10) {
                        Text(icon)
                            .font(.system(size: 48))

                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 6), spacing: 10) {
                            ForEach(iconOptions, id: \.self) { emoji in
                                Button {
                                    Haptics.selection()
                                    icon = emoji
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 28))
                                        .frame(width: 48, height: 48)
                                        .background(icon == emoji ? Color(hex: colorHex).opacity(0.15) : Color.clear)
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(AppFonts.label(12))
                            .foregroundColor(AppColors.textMuted)
                        TextField("e.g. Morning run", text: $title)
                            .font(AppFonts.body(16))
                            .padding(14)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                    }

                    // Color
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(AppFonts.label(12))
                            .foregroundColor(AppColors.textMuted)
                        HStack(spacing: 10) {
                            ForEach(colorOptions, id: \.self) { hex in
                                Button {
                                    Haptics.selection()
                                    colorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: colorHex == hex ? 3 : 0)
                                                .shadow(color: .black.opacity(0.2), radius: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Frequency
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Frequency")
                            .font(AppFonts.label(12))
                            .foregroundColor(AppColors.textMuted)

                        HStack(spacing: 8) {
                            frequencyPill("Daily", selected: frequency == .daily) {
                                frequency = .daily
                                selectedDays = Set(1...7)
                            }
                            frequencyPill("Specific Days", selected: frequency != .daily) {
                                frequency = .specificDays(selectedDays)
                            }
                        }

                        if frequency != .daily {
                            HStack(spacing: 6) {
                                ForEach(1...7, id: \.self) { weekday in
                                    Button {
                                        Haptics.selection()
                                        if selectedDays.contains(weekday) {
                                            if selectedDays.count > 1 {
                                                selectedDays.remove(weekday)
                                            }
                                        } else {
                                            selectedDays.insert(weekday)
                                        }
                                        frequency = .specificDays(selectedDays)
                                    } label: {
                                        Text(dayNames[weekday - 1])
                                            .font(AppFonts.label(12))
                                            .foregroundColor(selectedDays.contains(weekday) ? .white : AppColors.textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(selectedDays.contains(weekday) ? Color(hex: colorHex) : AppColors.surface)
                                            .cornerRadius(10)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(selectedDays.contains(weekday) ? Color.clear : AppColors.border, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Delete / Archive (edit mode only)
                    if isEditing {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                Text("Delete Habit")
                            }
                            .font(AppFonts.body(15))
                            .foregroundColor(AppColors.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.coral.opacity(0.08))
                            .cornerRadius(14)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Habit" : "New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .alert("Delete Habit", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let habit = existingHabit {
                        modelContext.delete(habit)
                        modelContext.safeSave()
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this habit and all its history.")
            }
        }
    }

    private func frequencyPill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label)
                .font(AppFonts.bodyMedium(14))
                .foregroundColor(selected ? .white : AppColors.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selected ? Color(hex: colorHex) : AppColors.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let habit = existingHabit {
            habit.title = trimmed
            habit.icon = icon
            habit.colorHex = colorHex
            habit.targetDays = frequency
        } else {
            let habit = HabitItem(
                title: trimmed,
                icon: icon,
                colorHex: colorHex,
                targetDays: frequency
            )
            modelContext.insert(habit)
        }

        modelContext.safeSave()
        Haptics.success()
        dismiss()
    }
}
