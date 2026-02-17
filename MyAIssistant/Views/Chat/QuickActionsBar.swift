import SwiftUI

struct QuickActionsBar: View {
    let actions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        Text(action)
                            .font(AppFonts.bodyMedium(13))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColors.accentLight)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
}
