import SwiftUI
import SwiftData

struct CheckInHistoryView: View {
    @Environment(\.checkInManager) private var checkInManager
    @Query(
        filter: #Predicate<CheckInRecord> { $0.completed == true },
        sort: \CheckInRecord.date,
        order: .reverse
    ) private var records: [CheckInRecord]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if records.isEmpty {
                        emptyState
                    } else {
                        ForEach(records, id: \.id) { record in
                            historyCard(record)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Check-in History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📋")
                .font(AppFonts.icon(40))
            Text("No check-ins yet")
                .font(AppFonts.heading(18))
                .foregroundColor(AppColors.textPrimary)
            Text("Complete your first check-in to see it here.")
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func historyCard(_ record: CheckInRecord) -> some View {
        let moods = ["", "😔", "😕", "😐", "🙂", "😄"]
        let moodEmoji = (record.mood != nil && record.mood! >= 1 && record.mood! <= 5)
            ? moods[record.mood!]
            : "—"

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.timeSlot.icon)
                    .font(AppFonts.icon(20))
                Text(record.timeSlot.title)
                    .font(AppFonts.bodyMedium(15))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(record.date.formatted(as: "MMM d, h:mm a"))
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)
            }

            HStack(spacing: 16) {
                Label(moodEmoji, systemImage: "face.smiling")
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)

                if let energy = record.energyLevel {
                    Label("\(energy)/5", systemImage: "bolt.fill")
                        .font(AppFonts.body(13))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            if let notes = record.notes, !notes.isEmpty {
                Text(notes)
                    .font(AppFonts.body(13))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(AppColors.card)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }
}
