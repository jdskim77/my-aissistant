import Foundation
import SwiftData

/// Exports user data (tasks, check-ins, activities, chat history) as a JSON file
/// for backup purposes. Prevents total data loss on device reset.
struct DataExportService {
    let modelContext: ModelContext

    func exportJSON() throws -> Data {
        let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
        let checkIns = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
        let activities = try modelContext.fetch(FetchDescriptor<ActivityEntry>())
        let chats = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let snapshots = try modelContext.fetch(FetchDescriptor<DailySnapshot>())

        let iso = ISO8601DateFormatter()

        let export: [String: Any] = [
            "exportDate": iso.string(from: Date()),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "tasks": tasks.map { t in
                [
                    "id": t.id,
                    "title": t.title,
                    "category": t.categoryRaw,
                    "priority": t.priorityRaw,
                    "date": iso.string(from: t.date),
                    "done": t.done,
                    "icon": t.icon,
                    "notes": t.notes,
                    "createdAt": iso.string(from: t.createdAt),
                    "completedAt": t.completedAt.map { iso.string(from: $0) } as Any,
                    "recurrence": t.recurrenceRaw as Any
                ] as [String: Any]
            },
            "checkIns": checkIns.map { c in
                [
                    "id": c.id,
                    "timeSlot": c.timeSlotRaw,
                    "date": iso.string(from: c.date),
                    "completed": c.completed,
                    "mood": c.mood as Any,
                    "energyLevel": c.energyLevel as Any,
                    "notes": c.notes as Any,
                    "aiSummary": c.aiSummary as Any
                ] as [String: Any]
            },
            "activities": activities.map { a in
                [
                    "id": a.id,
                    "activity": a.activity,
                    "category": a.category,
                    "date": iso.string(from: a.date),
                    "source": a.source
                ]
            },
            "chatMessages": chats.map { m in
                [
                    "id": m.id,
                    "role": m.roleRaw,
                    "content": m.content,
                    "timestamp": iso.string(from: m.timestamp),
                    "conversationID": m.conversationID
                ]
            },
            "dailySnapshots": snapshots.map { s in
                [
                    "id": s.id,
                    "date": iso.string(from: s.date),
                    "tasksTotal": s.tasksTotal,
                    "tasksCompleted": s.tasksCompleted,
                    "checkInsCompleted": s.checkInsCompleted,
                    "checkInsTotal": s.checkInsTotal,
                    "averageMood": s.averageMood as Any,
                    "streakCount": s.streakCount
                ] as [String: Any]
            }
        ]

        return try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    }

    func exportFileURL() throws -> URL {
        let data = try exportJSON()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "MyAIssistant-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
