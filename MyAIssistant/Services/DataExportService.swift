import Foundation
import SwiftData

/// Exports and imports all user data as JSON for backup/restore.
/// Covers every SwiftData model so users can recover data on a new device.
struct DataExportService {
    let modelContext: ModelContext

    private static let iso = ISO8601DateFormatter()

    // MARK: - Export

    func exportJSON() throws -> Data {
        let tasks = try modelContext.fetch(FetchDescriptor<TaskItem>())
        let checkIns = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
        let activities = try modelContext.fetch(FetchDescriptor<ActivityEntry>())
        let chats = try modelContext.fetch(FetchDescriptor<ChatMessage>())
        let snapshots = try modelContext.fetch(FetchDescriptor<DailySnapshot>())
        let balanceCheckIns = try modelContext.fetch(FetchDescriptor<DailyBalanceCheckIn>())
        let seasonGoals = try modelContext.fetch(FetchDescriptor<SeasonGoal>())
        let habits = try modelContext.fetch(FetchDescriptor<HabitItem>())
        let focusSessions = try modelContext.fetch(FetchDescriptor<FocusSession>())
        let patterns = try modelContext.fetch(FetchDescriptor<ActivityPattern>())
        let dimPrefs = try modelContext.fetch(FetchDescriptor<UserDimensionPreference>())

        let iso = Self.iso

        let export: [String: Any] = [
            "exportDate": iso.string(from: Date()),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "schemaVersion": 5,

            "tasks": tasks.map { t in
                var dict: [String: Any] = [
                    "id": t.id,
                    "title": t.title,
                    "category": t.categoryRaw,
                    "priority": t.priorityRaw,
                    "date": iso.string(from: t.date),
                    "done": t.done,
                    "icon": t.icon,
                    "notes": t.notes,
                    "createdAt": iso.string(from: t.createdAt)
                ]
                if let c = t.completedAt { dict["completedAt"] = iso.string(from: c) }
                if let r = t.recurrenceRaw { dict["recurrence"] = r }
                if let d = t.dimensionRaw { dict["dimension"] = d }
                if let e = t.effortRaw { dict["effort"] = e }
                if let ext = t.externalCalendarID { dict["externalCalendarID"] = ext }
                return dict
            },

            "checkIns": checkIns.map { c in
                var dict: [String: Any] = [
                    "id": c.id,
                    "timeSlot": c.timeSlotRaw,
                    "date": iso.string(from: c.date),
                    "completed": c.completed
                ]
                if let m = c.mood { dict["mood"] = m }
                if let e = c.energyLevel { dict["energyLevel"] = e }
                if let n = c.notes { dict["notes"] = n }
                if let a = c.aiSummary { dict["aiSummary"] = a }
                return dict
            },

            "activities": activities.map { a in
                [
                    "id": a.id,
                    "activity": a.activity,
                    "category": a.category,
                    "date": iso.string(from: a.date),
                    "source": a.source
                ] as [String: Any]
            },

            "chatMessages": chats.map { m in
                [
                    "id": m.id,
                    "role": m.roleRaw,
                    "content": m.content,
                    "timestamp": iso.string(from: m.timestamp),
                    "conversationID": m.conversationID
                ] as [String: Any]
            },

            "dailySnapshots": snapshots.map { s in
                var dict: [String: Any] = [
                    "id": s.id,
                    "date": iso.string(from: s.date),
                    "tasksTotal": s.tasksTotal,
                    "tasksCompleted": s.tasksCompleted,
                    "checkInsCompleted": s.checkInsCompleted,
                    "checkInsTotal": s.checkInsTotal,
                    "streakCount": s.streakCount
                ]
                if let m = s.averageMood { dict["averageMood"] = m }
                return dict
            },

            "balanceCheckIns": balanceCheckIns.map { b in
                var dict: [String: Any] = [
                    "id": b.id,
                    "date": iso.string(from: b.date),
                    "dimension": b.dimensionRaw
                ]
                if let e = b.energyRating { dict["energyRating"] = e }
                if let p = b.physicalSatisfaction { dict["physicalSatisfaction"] = p }
                if let m = b.mentalSatisfaction { dict["mentalSatisfaction"] = m }
                if let em = b.emotionalSatisfaction { dict["emotionalSatisfaction"] = em }
                if let s = b.spiritualSatisfaction { dict["spiritualSatisfaction"] = s }
                return dict
            },

            "seasonGoals": seasonGoals.map { g in
                var dict: [String: Any] = [
                    "id": g.id,
                    "dimensionRaw": g.dimensionRaw,
                    "intention": g.intention,
                    "startDate": iso.string(from: g.startDate),
                    "endDate": iso.string(from: g.endDate)
                ]
                if let c = g.completedAt { dict["completedAt"] = iso.string(from: c) }
                return dict
            },

            "habits": habits.map { h in
                [
                    "id": h.id,
                    "title": h.title,
                    "icon": h.icon,
                    "categoryRaw": h.categoryRaw,
                    "frequencyRaw": h.frequencyRaw,
                    "createdAt": iso.string(from: h.createdAt),
                    "archived": h.archived
                ] as [String: Any]
            },

            "focusSessions": focusSessions.map { f in
                [
                    "id": f.id,
                    "taskTitle": f.taskTitle,
                    "durationSeconds": f.durationSeconds,
                    "completedSeconds": f.completedSeconds,
                    "date": iso.string(from: f.date),
                    "completed": f.completed
                ] as [String: Any]
            },

            "activityPatterns": patterns.map { p in
                var dict: [String: Any] = [
                    "id": p.id,
                    "activityName": p.activityName,
                    "dimensionRaw": p.dimensionRaw,
                    "typicalDurationMinutes": p.typicalDurationMinutes,
                    "weekdayPatternRaw": p.weekdayPatternRaw,
                    "weeklyFrequency": p.weeklyFrequency,
                    "totalSuggested": p.totalSuggested,
                    "totalAccepted": p.totalAccepted,
                    "consecutiveDismissals": p.consecutiveDismissals,
                    "createdAt": iso.string(from: p.createdAt)
                ]
                if let ls = p.lastSuggested { dict["lastSuggested"] = iso.string(from: ls) }
                if let lc = p.lastConfirmed { dict["lastConfirmed"] = iso.string(from: lc) }
                return dict
            },

            "dimensionPreferences": dimPrefs.map { d in
                [
                    "id": d.id,
                    "dimensionRaw": d.dimensionRaw,
                    "weeklyTarget": d.weeklyTarget,
                    "isEnabled": d.isEnabled
                ] as [String: Any]
            }
        ]

        return try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    }

    func exportFileURL() throws -> URL {
        let data = try exportJSON()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "Thrivn-backup-\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }

    // MARK: - Import

    struct ImportResult {
        var tasksImported = 0
        var checkInsImported = 0
        var chatsImported = 0
        var otherImported = 0
        var skipped = 0
        var errors: [String] = []

        var summary: String {
            let total = tasksImported + checkInsImported + chatsImported + otherImported
            var parts: [String] = []
            if tasksImported > 0 { parts.append("\(tasksImported) tasks") }
            if checkInsImported > 0 { parts.append("\(checkInsImported) check-ins") }
            if chatsImported > 0 { parts.append("\(chatsImported) messages") }
            if otherImported > 0 { parts.append("\(otherImported) other records") }
            if skipped > 0 { parts.append("\(skipped) skipped (already exist)") }
            return total > 0 ? "Restored: " + parts.joined(separator: ", ") : "No new data to restore"
        }
    }

    func importJSON(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        let iso = Self.iso
        var result = ImportResult()

        // Import tasks
        if let tasks = json["tasks"] as? [[String: Any]] {
            for dict in tasks {
                guard let id = dict["id"] as? String else { continue }
                if taskExists(id: id) { result.skipped += 1; continue }

                guard let title = dict["title"] as? String,
                      let categoryRaw = dict["category"] as? String,
                      let priorityRaw = dict["priority"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }

                let task = TaskItem(
                    id: id,
                    title: title,
                    category: TaskCategory(rawValue: categoryRaw) ?? .personal,
                    priority: TaskPriority(rawValue: priorityRaw) ?? .medium,
                    date: date,
                    done: dict["done"] as? Bool ?? false,
                    icon: dict["icon"] as? String ?? "📋",
                    notes: dict["notes"] as? String ?? ""
                )
                if let completedStr = dict["completedAt"] as? String {
                    task.completedAt = iso.date(from: completedStr)
                }
                task.recurrenceRaw = dict["recurrence"] as? String
                task.dimensionRaw = dict["dimension"] as? String
                task.effortRaw = dict["effort"] as? String
                task.externalCalendarID = dict["externalCalendarID"] as? String
                modelContext.insert(task)
                result.tasksImported += 1
            }
        }

        // Import check-ins
        if let checkIns = json["checkIns"] as? [[String: Any]] {
            for dict in checkIns {
                guard let id = dict["id"] as? String else { continue }
                if checkInExists(id: id) { result.skipped += 1; continue }

                guard let timeSlot = dict["timeSlot"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }

                let record = CheckInRecord(
                    timeSlot: CheckInTime(rawValue: timeSlot) ?? .morning,
                    date: date,
                    completed: dict["completed"] as? Bool ?? true
                )
                record.mood = dict["mood"] as? Int
                record.energyLevel = dict["energyLevel"] as? Int
                record.notes = dict["notes"] as? String
                record.aiSummary = dict["aiSummary"] as? String
                modelContext.insert(record)
                result.checkInsImported += 1
            }
        }

        // Import chat messages
        if let chats = json["chatMessages"] as? [[String: Any]] {
            for dict in chats {
                guard let id = dict["id"] as? String else { continue }
                if chatExists(id: id) { result.skipped += 1; continue }

                guard let roleRaw = dict["role"] as? String,
                      let content = dict["content"] as? String,
                      let tsStr = dict["timestamp"] as? String,
                      let timestamp = iso.date(from: tsStr) else { continue }

                let msg = ChatMessage(
                    role: ChatMessage.Role(rawValue: roleRaw) ?? .user,
                    content: content,
                    conversationID: dict["conversationID"] as? String ?? "main"
                )
                modelContext.insert(msg)
                result.chatsImported += 1
            }
        }

        // Import balance check-ins
        if let balanceCheckIns = json["balanceCheckIns"] as? [[String: Any]] {
            for dict in balanceCheckIns {
                guard let id = dict["id"] as? String else { continue }
                if existsInDB(DailyBalanceCheckIn.self, id: id) { result.skipped += 1; continue }

                guard let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }

                let dimRaw = dict["dimension"] as? String ?? "Practical"
                let checkIn = DailyBalanceCheckIn(
                    dimension: LifeDimension(rawValue: dimRaw) ?? .practical,
                    energyRating: dict["energyRating"] as? Int,
                    physicalSatisfaction: dict["physicalSatisfaction"] as? Int,
                    mentalSatisfaction: dict["mentalSatisfaction"] as? Int,
                    emotionalSatisfaction: dict["emotionalSatisfaction"] as? Int,
                    spiritualSatisfaction: dict["spiritualSatisfaction"] as? Int,
                    date: date
                )
                modelContext.insert(checkIn)
                result.otherImported += 1
            }
        }

        // Import season goals
        if let goals = json["seasonGoals"] as? [[String: Any]] {
            for dict in goals {
                guard let id = dict["id"] as? String else { continue }
                if existsInDB(SeasonGoal.self, id: id) { result.skipped += 1; continue }

                guard let dimRaw = dict["dimensionRaw"] as? String,
                      let startStr = dict["startDate"] as? String,
                      let start = iso.date(from: startStr) else { continue }

                let goal = SeasonGoal(
                    dimension: LifeDimension(rawValue: dimRaw) ?? .physical,
                    intention: dict["intention"] as? String ?? ""
                )
                if let completedStr = dict["completedAt"] as? String {
                    goal.completedAt = iso.date(from: completedStr)
                }
                modelContext.insert(goal)
                result.otherImported += 1
            }
        }

        modelContext.safeSave()
        return result
    }

    // MARK: - Helpers

    private func taskExists(id: String) -> Bool {
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func checkInExists(id: String) -> Bool {
        let descriptor = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func chatExists(id: String) -> Bool {
        let descriptor = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func balanceCheckInExists(id: String) -> Bool {
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func seasonGoalExists(id: String) -> Bool {
        let descriptor = FetchDescriptor<SeasonGoal>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "The backup file is not a valid Thrivn backup."
            case .unsupportedVersion: return "This backup was created by a newer version of Thrivn."
            }
        }
    }
}
