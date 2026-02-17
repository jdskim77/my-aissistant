import SwiftUI

struct LoadingView: View {
    let lines: Int

    init(lines: Int = 3) {
        self.lines = lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<lines, id: \.self) { index in
                SkeletonLine(widthFraction: index == lines - 1 ? 0.6 : 1.0)
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
}

private struct SkeletonLine: View {
    let widthFraction: CGFloat
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColors.border.opacity(0.3),
                            AppColors.border.opacity(0.6),
                            AppColors.border.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * widthFraction, height: 12)
                .opacity(isAnimating ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isAnimating
                )
                .onAppear { isAnimating = true }
        }
        .frame(height: 12)
    }
}
