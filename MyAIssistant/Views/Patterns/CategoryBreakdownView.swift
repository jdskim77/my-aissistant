import SwiftUI

struct CategoryBreakdownView: View {
    let breakdown: [(category: TaskCategory, done: Int, total: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("By Category")
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)

            ForEach(breakdown, id: \.category) { item in
                let progress = item.total > 0 ? Double(item.done) / Double(item.total) : 0

                VStack(spacing: 6) {
                    HStack {
                        Text(item.category.icon)
                            .font(.system(size: 16))
                        Text(item.category.rawValue)
                            .font(AppFonts.bodyMedium(14))
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text("\(item.done)/\(item.total)")
                            .font(AppFonts.caption(13))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.border)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(categoryColor(item.category))
                                .frame(width: geo.size.width * progress, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(16)
        .background(AppColors.card)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .travel: return AppColors.skyBlue
        case .errand: return AppColors.gold
        case .personal: return AppColors.accentWarm
        case .work: return AppColors.accent
        case .health: return AppColors.coral
        }
    }
}
