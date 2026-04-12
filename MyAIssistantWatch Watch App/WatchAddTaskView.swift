#if os(watchOS)
import SwiftUI
import WatchKit
import WatchConnectivity

struct WatchAddTaskView: View {
    var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var priority = "Medium"
    @State private var hasTime = false
    @State private var taskDate = Date()
    @State private var selectedDimensions: Set<String> = []
    @State private var isSending = false
    @State private var showSuccess = false

    private let scoredDimensions: [(label: String, icon: String, color: Color)] = [
        ("Physical", "figure.run", .green),
        ("Mental", "brain.head.profile", .blue),
        ("Emotional", "heart.fill", .pink),
        ("Spiritual", "sparkles", .purple),
    ]

    var body: some View {
        List {
            Section {
                TextField("Task name", text: $title)
            }

            Section {
                Picker("Priority", selection: $priority) {
                    Label("High", systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .tag("High")
                    Label("Medium", systemImage: "circle.fill")
                        .foregroundColor(.orange)
                        .tag("Medium")
                    Label("Low", systemImage: "minus.circle.fill")
                        .foregroundColor(.blue)
                        .tag("Low")
                }
            }

            Section {
                Toggle(isOn: $hasTime) {
                    Label("Set time", systemImage: "clock")
                }

                if hasTime {
                    DatePicker("Time", selection: $taskDate, displayedComponents: .hourAndMinute)
                }
            }

            // Life Dimensions — 2x2 grid
            Section {
                Text("Life Dimensions")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(scoredDimensions, id: \.label) { dim in
                        dimensionButton(dim)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    addTask()
                } label: {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView()
                        } else if showSuccess {
                            Label("Added!", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Add Task", systemImage: "plus.circle.fill")
                        }
                        Spacer()
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSending || showSuccess)
                .listItemTint(showSuccess ? .green : .blue)
            }
        }
        .navigationTitle("New Task")
    }

    private func dimensionButton(_ dim: (label: String, icon: String, color: Color)) -> some View {
        let isSelected = selectedDimensions.contains(dim.label)
        return Button {
            WKInterfaceDevice.current().play(.click)
            if isSelected {
                selectedDimensions.remove(dim.label)
            } else if selectedDimensions.count < 3 {
                selectedDimensions.insert(dim.label)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: dim.icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                Text(dim.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundColor(isSelected ? .white : dim.color)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? dim.color : dim.color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dim.label)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(selectedDimensions.count >= 3 && !isSelected ? 0.4 : 1.0)
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSending = true
        WKInterfaceDevice.current().play(.success)

        var finalDate = Calendar.current.startOfDay(for: Date())
        if hasTime {
            let components = Calendar.current.dateComponents([.hour, .minute], from: taskDate)
            finalDate = Calendar.current.date(bySettingHour: components.hour ?? 9,
                                               minute: components.minute ?? 0,
                                               second: 0, of: finalDate) ?? finalDate
        }

        // Send via connectivity — include dimensions as comma-separated string
        // Sort dimensions for deterministic ordering in comma-separated string
        let dimString: String? = selectedDimensions.isEmpty ? nil :
            selectedDimensions.sorted().joined(separator: ",")
        connectivity.addTask(
            title: trimmed,
            priority: priority,
            date: finalDate,
            hasTime: hasTime,
            dimensions: dimString
        )

        Task {
            try? await Task.sleep(for: .milliseconds(300))
            isSending = false
            showSuccess = true
            try? await Task.sleep(for: .seconds(0.9))
            dismiss()
        }
    }
}

#endif
