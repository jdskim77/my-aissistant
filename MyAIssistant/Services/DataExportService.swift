import Foundation
import SwiftData

/// Exports and imports all user data as JSON for backup/restore.
/// Covers every SwiftData model so users can recover data on a new device.
struct DataExportService {
    let modelContext: ModelContext

    // Thread-local formatter to avoid thread safety issues
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    // MARK: - Export

    func exportJSON() throws -> Data {
        let iso = self.iso
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

        // Gather UserDefaults settings
        let settings = exportSettings()

        let export: [String: Any] = [
            "exportDate": iso.string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "schemaVersion": 5,
            "settings": settings,

            "tasks": tasks.map { t in
                var d: [String: Any] = [
                    "id": t.id, "title": t.title, "category": t.categoryRaw,
                    "priority": t.priorityRaw, "date": iso.string(from: t.date),
                    "done": t.done, "icon": t.icon, "notes": t.notes,
                    "createdAt": iso.string(from: t.createdAt)
                ]
                if let c = t.completedAt { d["completedAt"] = iso.string(from: c) }
                if let r = t.recurrenceRaw { d["recurrence"] = r }
                if let dm = t.dimensionRaw { d["dimension"] = dm }
                if let e = t.effortRaw { d["effort"] = e }
                if let ext = t.externalCalendarID { d["externalCalendarID"] = ext }
                return d
            },

            "checkIns": checkIns.map { c in
                var d: [String: Any] = [
                    "id": c.id, "timeSlot": c.timeSlotRaw,
                    "date": iso.string(from: c.date), "completed": c.completed
                ]
                if let m = c.mood { d["mood"] = m }
                if let e = c.energyLevel { d["energyLevel"] = e }
                if let n = c.notes { d["notes"] = n }
                if let a = c.aiSummary { d["aiSummary"] = a }
                return d
            },

            "activities": activities.map { a in
                ["id": a.id, "activity": a.activity, "category": a.category,
                 "date": iso.string(from: a.date), "source": a.source] as [String: Any]
            },

            "chatMessages": chats.map { m in
                ["id": m.id, "role": m.roleRaw, "content": m.content,
                 "timestamp": iso.string(from: m.timestamp),
                 "conversationID": m.conversationID] as [String: Any]
            },

            "dailySnapshots": snapshots.map { s in
                var d: [String: Any] = [
                    "id": s.id, "date": iso.string(from: s.date),
                    "tasksTotal": s.tasksTotal, "tasksCompleted": s.tasksCompleted,
                    "checkInsCompleted": s.checkInsCompleted, "checkInsTotal": s.checkInsTotal,
                    "streakCount": s.streakCount
                ]
                if let m = s.averageMood { d["averageMood"] = m }
                return d
            },

            "balanceCheckIns": balanceCheckIns.map { b in
                var d: [String: Any] = [
                    "id": b.id, "date": iso.string(from: b.date), "dimension": b.dimensionRaw
                ]
                if let e = b.energyRating { d["energyRating"] = e }
                if let p = b.physicalSatisfaction { d["physicalSatisfaction"] = p }
                if let m = b.mentalSatisfaction { d["mentalSatisfaction"] = m }
                if let em = b.emotionalSatisfaction { d["emotionalSatisfaction"] = em }
                if let s = b.spiritualSatisfaction { d["spiritualSatisfaction"] = s }
                return d
            },

            "seasonGoals": seasonGoals.map { g in
                var d: [String: Any] = [
                    "id": g.id, "dimensionRaw": g.dimensionRaw, "intention": g.intention,
                    "startDate": iso.string(from: g.startDate), "endDate": iso.string(from: g.endDate)
                ]
                if let c = g.completedAt { d["completedAt"] = iso.string(from: c) }
                return d
            },

            "habits": habits.map { h in
                var d: [String: Any] = [
                    "id": h.id, "title": h.title, "icon": h.icon,
                    "colorHex": h.colorHex, "createdAt": iso.string(from: h.createdAt),
                    "targetDaysRaw": h.targetDaysRaw, "completionDatesRaw": h.completionDatesRaw
                ]
                if let a = h.archivedAt { d["archivedAt"] = iso.string(from: a) }
                if let rh = h.reminderHour { d["reminderHour"] = rh }
                if let rm = h.reminderMinute { d["reminderMinute"] = rm }
                return d
            },

            "focusSessions": focusSessions.map { f in
                var d: [String: Any] = [
                    "id": f.id, "taskTitle": f.taskTitle,
                    "startedAt": iso.string(from: f.startedAt),
                    "workDuration": f.workDuration, "breakDuration": f.breakDuration,
                    "intervalsCompleted": f.intervalsCompleted,
                    "intervalsTarget": f.intervalsTarget,
                    "totalFocusSeconds": f.totalFocusSeconds, "completed": f.completed
                ]
                if let tid = f.taskID { d["taskID"] = tid }
                if let end = f.endedAt { d["endedAt"] = iso.string(from: end) }
                return d
            },

            "activityPatterns": patterns.map { p in
                var d: [String: Any] = [
                    "id": p.id, "activityName": p.activityName,
                    "dimensionRaw": p.dimensionRaw,
                    "typicalDurationMinutes": p.typicalDurationMinutes,
                    "weekdayPatternRaw": p.weekdayPatternRaw,
                    "weeklyFrequency": p.weeklyFrequency,
                    "totalSuggested": p.totalSuggested, "totalAccepted": p.totalAccepted,
                    "consecutiveDismissals": p.consecutiveDismissals,
                    "createdAt": iso.string(from: p.createdAt)
                ]
                if let ls = p.lastSuggested { d["lastSuggested"] = iso.string(from: ls) }
                if let lc = p.lastConfirmed { d["lastConfirmed"] = iso.string(from: lc) }
                return d
            },

            "dimensionPreferences": dimPrefs.map { dp in
                ["keyword": dp.keyword, "dimensionRaw": dp.dimensionRaw,
                 "confirmCount": dp.confirmCount, "totalCount": dp.totalCount,
                 "lastUpdated": iso.string(from: dp.lastUpdated)] as [String: Any]
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

    // MARK: - Settings Export/Import

    private func exportSettings() -> [String: Any] {
        let ud = UserDefaults.standard
        var s: [String: Any] = [:]
        s["theme"] = ud.string(forKey: AppConstants.appThemeKey)
        s["textSize"] = ud.string(forKey: AppConstants.textSizeKey)
        s["voiceModeDefault"] = ud.bool(forKey: AppConstants.voiceModeDefaultKey)
        s["selectedVoiceID"] = ud.string(forKey: AppConstants.selectedVoiceIDKey)
        s["voiceProvider"] = ud.string(forKey: AppConstants.voiceProviderKey)
        return s
    }

    private func importSettings(from dict: [String: Any]) {
        let ud = UserDefaults.standard
        if let theme = dict["theme"] as? String { ud.set(theme, forKey: AppConstants.appThemeKey) }
        if let textSize = dict["textSize"] as? String { ud.set(textSize, forKey: AppConstants.textSizeKey) }
        if let voice = dict["voiceModeDefault"] as? Bool { ud.set(voice, forKey: AppConstants.voiceModeDefaultKey) }
        if let voiceID = dict["selectedVoiceID"] as? String { ud.set(voiceID, forKey: AppConstants.selectedVoiceIDKey) }
        if let provider = dict["voiceProvider"] as? String { ud.set(provider, forKey: AppConstants.voiceProviderKey) }
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
            if skipped > 0 { parts.append("\(skipped) already existed") }
            return total > 0 ? "Restored: " + parts.joined(separator: ", ") : "No new data to restore"
        }
    }

    func importJSON(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        // Validate it's a Thrivn backup (must have exportDate)
        guard json["exportDate"] != nil else {
            throw ImportError.invalidFormat
        }

        // Check schema version
        if let schemaVersion = json["schemaVersion"] as? Int, schemaVersion > 5 {
            throw ImportError.unsupportedVersion
        }

        let iso = self.iso
        var result = ImportResult()

        // Import settings
        if let settings = json["settings"] as? [String: Any] {
            importSettings(from: settings)
        }

        // 1. Tasks
        if let tasks = json["tasks"] as? [[String: Any]] {
            for dict in tasks {
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }
                if taskExists(id: id) { result.skipped += 1; continue }

                let task = TaskItem(
                    id: id,
                    title: title,
                    category: TaskCategory(rawValue: dict["category"] as? String ?? "") ?? .personal,
                    priority: TaskPriority(rawValue: dict["priority"] as? String ?? "") ?? .medium,
                    date: date,
                    done: dict["done"] as? Bool ?? false,
                    icon: dict["icon"] as? String ?? "📋",
                    notes: dict["notes"] as? String ?? ""
                )
                // Restore createdAt from backup
                if let createdStr = dict["createdAt"] as? String, let created = iso.date(from: createdStr) {
                    task.createdAt = created
                }
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

        // 2. CheckIns
        if let checkIns = json["checkIns"] as? [[String: Any]] {
            for dict in checkIns {
                guard let id = dict["id"] as? String,
                      let timeSlot = dict["timeSlot"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }
                if checkInExists(id: id) { result.skipped += 1; continue }

                let record = CheckInRecord(
                    id: id,
                    timeSlot: CheckInTime(rawValue: timeSlot) ?? .morning,
                    date: date,
                    completed: dict["completed"] as? Bool ?? true,
                    mood: dict["mood"] as? Int,
                    energyLevel: dict["energyLevel"] as? Int,
                    notes: dict["notes"] as? String,
                    aiSummary: dict["aiSummary"] as? String
                )
                modelContext.insert(record)
                result.checkInsImported += 1
            }
        }

        // 3. Chat Messages
        if let chats = json["chatMessages"] as? [[String: Any]] {
            for dict in chats {
                guard let id = dict["id"] as? String,
                      let roleRaw = dict["role"] as? String,
                      let content = dict["content"] as? String else { continue }
                if chatExists(id: id) { result.skipped += 1; continue }

                let timestamp: Date
                if let tsStr = dict["timestamp"] as? String, let ts = iso.date(from: tsStr) {
                    timestamp = ts
                } else {
                    timestamp = Date()
                }

                let msg = ChatMessage(
                    id: id,
                    role: MessageRole(rawValue: roleRaw) ?? .user,
                    content: content,
                    timestamp: timestamp,
                    conversationID: dict["conversationID"] as? String ?? "main"
                )
                modelContext.insert(msg)
                result.chatsImported += 1
            }
        }

        // 4. Balance CheckIns
        if let balanceCheckIns = json["balanceCheckIns"] as? [[String: Any]] {
            for dict in balanceCheckIns {
                guard let id = dict["id"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }
                if balanceCheckInExists(id: id) { result.skipped += 1; continue }

                let checkIn = DailyBalanceCheckIn(
                    dimension: LifeDimension(rawValue: dict["dimension"] as? String ?? "") ?? .practical,
                    energyRating: dict["energyRating"] as? Int,
                    physicalSatisfaction: dict["physicalSatisfaction"] as? Int,
                    mentalSatisfaction: dict["mentalSatisfaction"] as? Int,
                    emotionalSatisfaction: dict["emotionalSatisfaction"] as? Int,
                    spiritualSatisfaction: dict["spiritualSatisfaction"] as? Int,
                    date: date
                )
                // Override the auto-generated ID with the backup's ID for dedup
                checkIn.id = id
                modelContext.insert(checkIn)
                result.otherImported += 1
            }
        }

        // 5. Season Goals
        if let goals = json["seasonGoals"] as? [[String: Any]] {
            for dict in goals {
                guard let id = dict["id"] as? String,
                      let dimRaw = dict["dimensionRaw"] as? String else { continue }
                if seasonGoalExists(id: id) { result.skipped += 1; continue }

                let goal = SeasonGoal(
                    dimension: LifeDimension(rawValue: dimRaw) ?? .physical,
                    intention: dict["intention"] as? String ?? ""
                )
                // Override auto-generated dates with backup values
                goal.id = id
                if let startStr = dict["startDate"] as? String, let start = iso.date(from: startStr) {
                    goal.startDate = start
                }
                if let endStr = dict["endDate"] as? String, let end = iso.date(from: endStr) {
                    goal.endDate = end
                }
                if let completedStr = dict["completedAt"] as? String {
                    goal.completedAt = iso.date(from: completedStr)
                }
                modelContext.insert(goal)
                result.otherImported += 1
            }
        }

        // 6. Activities
        if let activities = json["activities"] as? [[String: Any]] {
            for dict in activities {
                guard let id = dict["id"] as? String,
                      let activity = dict["activity"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }
                if activityExists(id: id) { result.skipped += 1; continue }

                let entry = ActivityEntry(
                    activity: activity,
                    category: dict["category"] as? String ?? "",
                    date: date,
                    source: dict["source"] as? String ?? "manual"
                )
                entry.id = id
                modelContext.insert(entry)
                result.otherImported += 1
            }
        }

        // 7. Daily Snapshots
        if let snapshots = json["dailySnapshots"] as? [[String: Any]] {
            for dict in snapshots {
                guard let id = dict["id"] as? String,
                      let dateStr = dict["date"] as? String,
                      let date = iso.date(from: dateStr) else { continue }
                if snapshotExists(id: id) { result.skipped += 1; continue }

                let snapshot = DailySnapshot(
                    date: date,
                    tasksTotal: dict["tasksTotal"] as? Int ?? 0,
                    tasksCompleted: dict["tasksCompleted"] as? Int ?? 0,
                    checkInsCompleted: dict["checkInsCompleted"] as? Int ?? 0,
                    checkInsTotal: dict["checkInsTotal"] as? Int ?? 0,
                    streakCount: dict["streakCount"] as? Int ?? 0,
                    averageMood: dict["averageMood"] as? Double
                )
                snapshot.id = id
                modelContext.insert(snapshot)
                result.otherImported += 1
            }
        }

        // 8. Habits
        if let habits = json["habits"] as? [[String: Any]] {
            for dict in habits {
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String else { continue }
                if habitExists(id: id) { result.skipped += 1; continue }

                let habit = HabitItem(
                    title: title,
                    icon: dict["icon"] as? String ?? "⭐",
                    colorHex: dict["colorHex"] as? String ?? "4CAF50"
                )
                habit.id = id
                habit.targetDaysRaw = dict["targetDaysRaw"] as? String ?? "daily"
                habit.completionDatesRaw = dict["completionDatesRaw"] as? String ?? ""
                if let createdStr = dict["createdAt"] as? String, let created = iso.date(from: createdStr) {
                    habit.createdAt = created
                }
                if let archivedStr = dict["archivedAt"] as? String {
                    habit.archivedAt = iso.date(from: archivedStr)
                }
                habit.reminderHour = dict["reminderHour"] as? Int
                habit.reminderMinute = dict["reminderMinute"] as? Int
                modelContext.insert(habit)
                result.otherImported += 1
            }
        }

        // 9. Focus Sessions
        if let sessions = json["focusSessions"] as? [[String: Any]] {
            for dict in sessions {
                guard let id = dict["id"] as? String,
                      let taskTitle = dict["taskTitle"] as? String,
                      let startStr = dict["startedAt"] as? String,
                      let startedAt = iso.date(from: startStr) else { continue }
                if focusSessionExists(id: id) { result.skipped += 1; continue }

                let session = FocusSession(
                    taskTitle: taskTitle,
                    workDuration: dict["workDuration"] as? Int ?? 1500,
                    breakDuration: dict["breakDuration"] as? Int ?? 300,
                    intervalsTarget: dict["intervalsTarget"] as? Int ?? 4
                )
                session.id = id
                session.taskID = dict["taskID"] as? String
                session.startedAt = startedAt
                if let endStr = dict["endedAt"] as? String { session.endedAt = iso.date(from: endStr) }
                session.intervalsCompleted = dict["intervalsCompleted"] as? Int ?? 0
                session.totalFocusSeconds = dict["totalFocusSeconds"] as? Int ?? 0
                session.completed = dict["completed"] as? Bool ?? false
                modelContext.insert(session)
                result.otherImported += 1
            }
        }

        // 10. Activity Patterns
        if let patterns = json["activityPatterns"] as? [[String: Any]] {
            for dict in patterns {
                guard let id = dict["id"] as? String,
                      let name = dict["activityName"] as? String,
                      let dimRaw = dict["dimensionRaw"] as? String else { continue }
                if patternExists(id: id) { result.skipped += 1; continue }

                let pattern = ActivityPattern(
                    activityName: name,
                    dimension: LifeDimension(rawValue: dimRaw) ?? .physical,
                    typicalDurationMinutes: dict["typicalDurationMinutes"] as? Int ?? 30,
                    weekdayPattern: (dict["weekdayPatternRaw"] as? String ?? "").split(separator: ",").compactMap { Int($0) },
                    weeklyFrequency: dict["weeklyFrequency"] as? Int ?? 3
                )
                pattern.id = id
                pattern.totalSuggested = dict["totalSuggested"] as? Int ?? 0
                pattern.totalAccepted = dict["totalAccepted"] as? Int ?? 0
                pattern.consecutiveDismissals = dict["consecutiveDismissals"] as? Int ?? 0
                if let createdStr = dict["createdAt"] as? String { pattern.createdAt = iso.date(from: createdStr) ?? Date() }
                if let lsStr = dict["lastSuggested"] as? String { pattern.lastSuggested = iso.date(from: lsStr) }
                if let lcStr = dict["lastConfirmed"] as? String { pattern.lastConfirmed = iso.date(from: lcStr) }
                modelContext.insert(pattern)
                result.otherImported += 1
            }
        }

        // 11. Dimension Preferences
        if let prefs = json["dimensionPreferences"] as? [[String: Any]] {
            for dict in prefs {
                guard let keyword = dict["keyword"] as? String,
                      let dimRaw = dict["dimensionRaw"] as? String else { continue }
                if dimPrefExists(keyword: keyword) { result.skipped += 1; continue }

                let pref = UserDimensionPreference(
                    keyword: keyword,
                    dimension: LifeDimension(rawValue: dimRaw) ?? .physical
                )
                pref.confirmCount = dict["confirmCount"] as? Int ?? 0
                pref.totalCount = dict["totalCount"] as? Int ?? 0
                if let updatedStr = dict["lastUpdated"] as? String, let updated = iso.date(from: updatedStr) {
                    pref.lastUpdated = updated
                }
                modelContext.insert(pref)
                result.otherImported += 1
            }
        }

        modelContext.safeSave()
        return result
    }

    // MARK: - Dedup Helpers (one per model type)

    private func taskExists(id: String) -> Bool {
        let d = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func checkInExists(id: String) -> Bool {
        let d = FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func chatExists(id: String) -> Bool {
        let d = FetchDescriptor<ChatMessage>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func balanceCheckInExists(id: String) -> Bool {
        let d = FetchDescriptor<DailyBalanceCheckIn>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func seasonGoalExists(id: String) -> Bool {
        let d = FetchDescriptor<SeasonGoal>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func activityExists(id: String) -> Bool {
        let d = FetchDescriptor<ActivityEntry>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func snapshotExists(id: String) -> Bool {
        let d = FetchDescriptor<DailySnapshot>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func habitExists(id: String) -> Bool {
        let d = FetchDescriptor<HabitItem>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func focusSessionExists(id: String) -> Bool {
        let d = FetchDescriptor<FocusSession>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func patternExists(id: String) -> Bool {
        let d = FetchDescriptor<ActivityPattern>(predicate: #Predicate { $0.id == id })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    private func dimPrefExists(keyword: String) -> Bool {
        let d = FetchDescriptor<UserDimensionPreference>(predicate: #Predicate { $0.keyword == keyword })
        return ((try? modelContext.fetchCount(d)) ?? 0) > 0
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        case unsupportedVersion

        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "This file is not a valid Thrivn backup."
            case .unsupportedVersion: return "This backup was created by a newer version of Thrivn. Please update the app."
            }
        }
    }
}
