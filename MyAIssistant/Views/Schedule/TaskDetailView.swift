import SwiftUI

struct TaskDetailView: View {
    @Environment(\.taskManager) private var taskManager
    @Environment(\.dismiss) private var dismiss

    let task: TaskItem

    @State private var title: String
    @State private var date: Date
    @State private var category: TaskCategory
    @State private var priority: TaskPriority
    @State private var notes: String
    @State private var icon: String
    @State private var showingDeleteAlert = false

    private let iconOptions = ["📌", "✈️", "🏨", "🚐", "🧳", "🛫", "🛬", "🏜️", "💱", "📋", "📘", "🛒", "💳", "🔧", "🧘", "📞", "💊", "🎁", "📦", "🏃"]

    init(task: TaskItem) {
        self.task = task
        self._title = State(initialValue: task.title)
        self._date = State(initialValue: task.date)
        self._category = State(initialValue: task.category)
        self._priority = State(initialValue: task.priority)
        self._notes = State(initialValue: task.notes)
        self._icon = State(initialValue: task.icon)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status
                    HStack(spacing: 10) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(AppFonts.icon(22))
                            .foregroundColor(task.done ? AppColors.accentWarm : AppColors.textMuted)

                        Text(task.done ? "Completed" : "Pending")
                            .font(AppFonts.bodyMedium(15))
                            .foregroundColor(task.done ? AppColors.accentWarm : AppColors.textSecondary)

                        Spacer()

                        Button {
                            taskManager?.toggleCompletion(task)
                        } label: {
                            Text(task.done ? "Mark Pending" : "Mark Done")
                                .font(AppFonts.bodyMedium(13))
                                .foregroundColor(AppColors.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(AppColors.accentLight)
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                    .background(AppColors.card)
                    .cornerRadius(14)

                    // Icon picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(iconOptions, id: \.self) { opt in
                                    Button {
                                        icon = opt
                                    } label: {
                                        Text(opt)
                                            .font(AppFonts.icon(22))
                                            .padding(6)
                                            .background(icon == opt ? AppColors.accentLight : Color.clear)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        TextField("Task title", text: $title)
                            .font(AppFonts.body(15))
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }

                    // Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Due Date")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(AppColors.accent)
                    }

                    // Category
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(TaskCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    Text(cat.rawValue)
                                        .font(AppFonts.bodyMedium(13))
                                        .foregroundColor(category == cat ? .white : AppColors.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(category == cat ? AppColors.accent : AppColors.surface)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(category == cat ? Color.clear : AppColors.border, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Priority")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(TaskPriority.allCases) { pri in
                                Button {
                                    priority = pri
                                } label: {
                                    Text(pri.rawValue)
                                        .font(AppFonts.bodyMedium(13))
                                        .foregroundColor(priority == pri ? .white : AppColors.priorityColor(pri))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(priority == pri ? AppColors.priorityColor(pri) : AppColors.priorityColor(pri).opacity(0.1))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(AppFonts.heading(14))
                            .foregroundColor(AppColors.textSecondary)

                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .font(AppFonts.body(14))
                            .lineLimit(3...6)
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }

                    // Calendar source info
                    if let sourceLabel = taskManager?.calendarSourceLabel(task) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(AppFonts.caption(13))
                            Text("Imported from \(sourceLabel)")
                                .font(AppFonts.caption(12))
                        }
                        .foregroundColor(AppColors.textMuted)
                    }

                    // Delete button
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .font(AppFonts.bodyMedium(14))
                            Text("Delete Task")
                                .font(AppFonts.bodyMedium(15))
                        }
                        .foregroundColor(AppColors.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.coral.opacity(0.08))
                        .cornerRadius(10)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .font(AppFonts.bodyMedium(15))
                    .disabled(title.isEmpty)
                }
            }
            .alert("Delete Task", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    taskManager?.deleteTask(task)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(task.title)\"? This cannot be undone.")
            }
        }
    }

    private func saveChanges() {
        task.title = title
        task.date = date
        task.category = category
        task.priority = priority
        task.notes = notes
        task.icon = icon
    }
}
