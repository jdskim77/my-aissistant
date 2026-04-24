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
    @Environment(\.habitManager) private var habitManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let mode: Mode

    @State private var title: String
    /// Focus tracker for the title TextField. Enables the keyboard
    /// toolbar Done button, which the project's text-input rules
    /// require on every TextField. Fix for Q2-BUG-12.
    @FocusState private var titleFocused: Bool
    @State private var icon: String
    @State private var colorHex: String
    @State private var frequency: HabitFrequency
    @State private var selectedDays: Set<Int>
    @State private var dimension: LifeDimension?
    @State private var timeWindow: HabitTimeWindow?
    @State private var showDeleteConfirm = false

    private let colorOptions = ["#2D5016", "#1A5276", "#B8860B", "#C94B2B", "#5856D6", "#34C759", "#FF9500", "#007AFF"]
    private let iconOptions = ["💪", "📚", "🏃", "💧", "🧘", "✍️", "🎯", "💤", "🥗", "🎸", "📝", "🧹"]
    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// Effective color for the habit's accents. When a dimension is chosen
    /// we show the dimension color so the habit visually identifies with its
    /// Compass quadrant; otherwise fall back to the user's manual pick.
    private var effectiveColorHex: String {
        dimension.map { "#" + $0.colorHex } ?? colorHex
    }

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
            _dimension = State(initialValue: nil)
            _timeWindow = State(initialValue: nil)
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
            _dimension = State(initialValue: habit.dimension)
            _timeWindow = State(initialValue: habit.timeWindow)
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
                                        .background(icon == emoji ? Color(hex: effectiveColorHex).opacity(0.15) : Color.clear)
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
                            .focused($titleFocused)
                            .padding(14)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") { titleFocused = false }
                                }
                            }
                    }

                    // Life dimension — ties the habit to a Compass quadrant.
                    // When set, the habit contributes to its dimension's score
                    // and uses the dimension color throughout. "None" keeps the
                    // habit untagged and exposes the manual color picker.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Life Dimension")
                            .font(AppFonts.label(12))
                            .foregroundColor(AppColors.textMuted)

                        // 4 scored dimensions + None. Two rows to avoid
                        // squeezing labels at smaller Dynamic Type sizes.
                        LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 8) {
                            ForEach(LifeDimension.scored) { dim in
                                dimensionPill(dim)
                            }
                            nonePill
                        }

                        if let dim = dimension {
                            Text(dim.summary)
                                .font(AppFonts.caption(11))
                                .foregroundColor(AppColors.textMuted)
                                .padding(.top, 2)
                        }
                    }

                    // Manual color — only shown when the habit is untagged.
                    // Tagged habits use the dimension color so they identify
                    // visually with their Compass quadrant.
                    if dimension == nil {
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
                                            .background(selectedDays.contains(weekday) ? Color(hex: effectiveColorHex) : AppColors.surface)
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

                    // Time of day window — picks the fuzzy 4-hour band
                    // this habit belongs to. Controls visual emphasis
                    // (dim outside window) and coach nudge targeting.
                    // Streak credit is intentionally independent of
                    // this setting — completing a morning habit at 2pm
                    // still earns today's streak.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Time of day")
                            .font(AppFonts.label(12))
                            .foregroundColor(AppColors.textMuted)

                        timeWindowPicker

                        Text("Shown prominently during this window. Counts toward your streak any time you complete it.")
                            .font(AppFonts.caption(11))
                            .foregroundColor(AppColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
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
            .scrollDismissesKeyboard(.interactively)
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
                        habitManager?.delete(habit)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete this habit and all its history.")
            }
        }
    }

    /// 5-option picker: Any time + 4 windows. SF Symbols + labels.
    /// Adapts to Dynamic Type — LazyVGrid (2-column) at accessibility
    /// sizes so long labels like "Afternoon" don't get truncated off
    /// the right edge of a horizontal ScrollView (BUG-05). Below AX
    /// sizes, horizontal scroll with visible indicators so users at
    /// L/XL text know there's more to swipe to.
    @ViewBuilder
    private var timeWindowPicker: some View {
        let options: [(label: String, symbol: String, value: HabitTimeWindow?)] = [
            ("Any time", "clock", nil),
            ("Morning", HabitTimeWindow.morning.sfSymbol, .morning),
            ("Midday", HabitTimeWindow.midday.sfSymbol, .midday),
            ("Afternoon", HabitTimeWindow.afternoon.sfSymbol, .afternoon),
            ("Night", HabitTimeWindow.night.sfSymbol, .night)
        ]
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 8) {
                ForEach(options, id: \.label) { option in
                    timeWindowChip(option: option)
                }
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.label) { option in
                        timeWindowChip(option: option)
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }

    @ViewBuilder
    private func timeWindowChip(option: (label: String, symbol: String, value: HabitTimeWindow?)) -> some View {
        let isSelected = timeWindow == option.value
        Button {
            Haptics.selection()
            timeWindow = option.value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(option.label)
                    .font(AppFonts.bodyMedium(13))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 14)
            .background(isSelected ? Color(hex: effectiveColorHex) : AppColors.surface)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label) time window")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dimensionPill(_ dim: LifeDimension) -> some View {
        let isSelected = dimension == dim
        return Button {
            Haptics.selection()
            dimension = (isSelected ? nil : dim)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: dim.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(dim.label)
                    .font(AppFonts.bodyMedium(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isSelected ? .white : dim.color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(isSelected ? dim.color : dim.color.opacity(0.10))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.clear : dim.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dim.label) dimension\(isSelected ? ", selected" : "")")
    }

    private var nonePill: some View {
        let isSelected = dimension == nil
        return Button {
            Haptics.selection()
            dimension = nil
        } label: {
            Text("None")
                .font(AppFonts.bodyMedium(13))
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isSelected ? AppColors.textSecondary : AppColors.surface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No dimension\(isSelected ? ", selected" : "")")
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
                .frame(minHeight: 44)
                .background(selected ? Color(hex: effectiveColorHex) : AppColors.surface)
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

        // Persist the user's MANUAL color pick unconditionally. The dimension
        // color is derived at read-time via `HabitItem.effectiveColor`, so
        // overwriting `colorHex` with the dimension's hex would destroy the
        // user's pick and show stale color if they later clear the dimension.
        if let habit = existingHabit {
            habit.title = trimmed
            habit.icon = icon
            habit.colorHex = colorHex
            habit.targetDays = frequency
            habit.timeWindow = timeWindow
            // Guard: only overwrite dimensions if the user's selection
            // actually differs from the habit's current primary dimension.
            // A Save with no changes should not destroy any secondary
            // dimensions a multi-tagged habit may have.
            if habit.dimension != dimension {
                habit.dimension = dimension
            }
            habitManager?.save(habit)
        } else {
            let habit = HabitItem(
                title: trimmed,
                icon: icon,
                colorHex: colorHex,
                targetDays: frequency,
                dimension: dimension
            )
            habit.timeWindow = timeWindow
            habitManager?.save(habit)
        }

        Haptics.success()
        dismiss()
    }
}
