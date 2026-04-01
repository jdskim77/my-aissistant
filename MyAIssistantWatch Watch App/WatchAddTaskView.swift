#if os(watchOS)
import SwiftUI
import WatchKit

struct WatchAddTaskView: View {
    var connectivity: WatchConnectivityManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var priority = "Medium"
    @State private var hasTime = false
    @State private var taskDate = Date()
    @State private var isSending = false
    @State private var showSuccess = false

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

        connectivity.addTask(
            title: trimmed,
            priority: priority,
            date: finalDate,
            hasTime: hasTime
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSending = false
            showSuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}

#endif
