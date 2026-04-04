import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class CheckInManager {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Start Check-in

    func startCheckIn(timeSlot: CheckInTime) -> CheckInRecord {
        let record = CheckInRecord(timeSlot: timeSlot)
        modelContext.insert(record)
        modelContext.safeSave()
        return record
    }

    // MARK: - Complete Check-in

    func completeCheckIn(
        _ record: CheckInRecord,
        mood: Int,
        energyLevel: Int?,
        notes: String?,
        aiSummary: String?
    ) {
        record.completed = true
        record.mood = mood
        record.energyLevel = energyLevel
        record.notes = notes
        record.aiSummary = aiSummary
        modelContext.safeSave()
    }

    // MARK: - Generate AI Greeting

    func generateGreeting(
        timeSlot: CheckInTime,
        mood: Int?,
        keychain: KeychainService,
        tier: SubscriptionTier,
        scheduleSummary: String,
        completionRate: Int,
        streak: Int
    ) async -> String {
        do {
            let provider = try AIProviderFactory.provider(
                for: tier,
                useCase: .checkIn,
                keychain: keychain
            )

            let systemPrompt = AIPromptBuilder.checkInPrompt(
                timeSlot: timeSlot.rawValue,
                scheduleSummary: scheduleSummary,
                completionRate: completionRate,
                streak: streak,
                mood: mood
            )

            let response = try await provider.sendMessage(
                userMessage: "Begin my \(timeSlot.rawValue.lowercased()) check-in.",
                conversationHistory: [],
                systemPrompt: systemPrompt
            )

            return response.content
        } catch {
            return timeSlot.greeting
        }
    }

    // MARK: - Queries

    func todayCheckIns() -> [CheckInRecord] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.safeDate(byAdding: .day, value: 1, to: startOfDay)

        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.date >= startOfDay && $0.date < endOfDay },
            sortBy: [SortDescriptor(\CheckInRecord.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func isCheckInCompleted(_ timeSlot: CheckInTime) -> Bool {
        let slotRaw = timeSlot.rawValue
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.safeDate(byAdding: .day, value: 1, to: startOfDay)

        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate {
                $0.timeSlotRaw == slotRaw && $0.completed == true &&
                $0.date >= startOfDay && $0.date < endOfDay
            }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    func recentCheckIns(limit: Int = 20) -> [CheckInRecord] {
        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.completed == true },
            sortBy: [SortDescriptor(\CheckInRecord.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
