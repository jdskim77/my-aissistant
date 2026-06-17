import Foundation
import SwiftData

/// Persists and reads the user's daily balance check-in — per-dimension
/// satisfaction ratings and energy. Extracted verbatim from `BalanceManager`,
/// which keeps the public API and delegates here, so that type can stay
/// focused on scoring. Pure SwiftData CRUD on `DailyBalanceCheckIn`.
@MainActor
struct BalanceCheckInStore {
    let modelContext: ModelContext

    /// Record satisfaction ratings for all dimensions at once during a check-in.
    func recordSatisfaction(ratings: [LifeDimension: Int], energyRating: Int? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)

        // Find or create today's check-in. Range predicate (not `== today`)
        // tolerates sub-second drift that can sneak in through CloudKit
        // round-trips, Watch sync, or any path that doesn't pin the date to
        // exact midnight — without it we were inserting duplicate rows.
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        let existing = try? modelContext.fetch(descriptor).first

        let checkIn = existing ?? DailyBalanceCheckIn(date: today)
        if existing == nil {
            modelContext.insert(checkIn)
        }

        for (dim, rating) in ratings {
            checkIn.setSatisfaction(max(1, min(5, rating)), for: dim)
        }
        if let energy = energyRating {
            checkIn.energyRating = energy
        }

        // Set the "best energy" dimension to the one with highest rating
        if let best = ratings.max(by: { $0.value < $1.value }) {
            checkIn.dimension = best.key
        }

        modelContext.safeSave()
    }

    /// Legacy: Record a single-dimension check-in (backwards compatible).
    func recordCheckIn(dimension: LifeDimension, energyRating: Int? = nil) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
        }
        let checkIn = DailyBalanceCheckIn(dimension: dimension, energyRating: energyRating)
        modelContext.insert(checkIn)
        modelContext.safeSave()
    }

    /// Whether the user has completed today's balance check-in.
    func hasCheckedInToday() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Today's satisfaction ratings, if any.
    func todaySatisfaction() -> [LifeDimension: Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.safeDate(byAdding: .day, value: 1, to: today)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        guard let checkIn = try? modelContext.fetch(descriptor).first else { return [:] }
        var result: [LifeDimension: Int] = [:]
        for dim in LifeDimension.scored {
            if let rating = checkIn.satisfaction(for: dim) {
                result[dim] = rating
            }
        }
        return result
    }

    /// Average energy rating for the current week (-3 to +3), or nil if no ratings.
    func weeklyEnergyAverage() -> Double? {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let end = calendar.safeDate(byAdding: .day, value: 7, to: start)
        let descriptor = FetchDescriptor<DailyBalanceCheckIn>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        let checkIns = (try? modelContext.fetch(descriptor)) ?? []
        let rated = checkIns.compactMap(\.energyRating)
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }
}
