import SwiftUI

/// Short photo-strip hero at the top of Today (phase 1 of the Today
/// redesign). Joe's own surf photo, full card width, clipped to a
/// 14pt-radius band with the top of the frame favoured so the surfer
/// stays visible at the ~128pt height used here. Decorative — hidden
/// from VoiceOver; the real content lives in whatever is passed as
/// `content` (the Tonight card's next-action row, or the normal hero's
/// action row), rendered directly beneath the photo inside the SAME
/// card so there's no visual seam between "photo" and "next thing."
struct TodayHeroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    private let photoHeight: CGFloat = 128
    /// 14pt corner radius per the approved Today-redesign spec — not one
    /// of the existing `AppRadius` steps (6/12/16/20), so it's a literal
    /// here rather than a mismatched token.
    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("TodayHero")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: photoHeight, alignment: .top)
                // Favour the top/centre of the frame so the surfer stays
                // in view regardless of the device's aspect ratio —
                // `alignment: .top` above biases the crop upward before
                // `.clipped()` trims the overflow.
                .clipped()
                .accessibilityHidden(true)

            content()
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(AppColors.card)
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
        )
        // Clip the whole card (photo + content) to one consistent
        // 14pt-radius shape so the photo's corners and the content
        // card's corners read as a single surface, in both light and
        // dark mode.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
