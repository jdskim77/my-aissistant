import SwiftUI
import SwiftData

/// Horizontal scrolling date strip showing 7+ days with task density indicators.
struct DayTickerView: View {
    @Binding var selectedDate: Date
    let taskCounts: [Date: Int] // startOfDay -> task count for density dots

    private let calendar = Calendar.current
    private let dayRange = -3...14 // 3 days back, 14 days forward

    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return dayRange.compactMap { offset in
            calendar.safeDate(byAdding: .day, value: offset, to: today)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(days, id: \.self) { day in
                        dayCell(day)
                            .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                let today = calendar.startOfDay(for: Date())
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(today, anchor: .center)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let count = taskCounts[calendar.startOfDay(for: day)] ?? 0

        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3)) {
                selectedDate = day
            }
        } label: {
            VStack(spacing: 4) {
                Text(dayAbbrev(day))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : isToday ? AppColors.accent : AppColors.textMuted)

                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 17, weight: isSelected || isToday ? .bold : .semibold))
                    .foregroundColor(isSelected ? .white : isToday ? AppColors.accent : AppColors.textPrimary)

                // Density dots
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 4), id: \.self) { _ in
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.7) : AppColors.accent.opacity(0.6))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(width: 48, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AppColors.accent : isToday ? AppColors.accentLight.opacity(0.4) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dayFull(day)), \(count) tasks")
    }

    private func dayAbbrev(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayFull(_ date: Date) -> String {
        date.formatted(as: "EEEE, MMMM d")
    }
}
