import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    /// Show the safety bubble variant ONLY for assistant-side messages.
    /// User-side messages flagged `isSafetyResource` (the user's crisis
    /// input) render as normal user bubbles — we never reframe what the
    /// user wrote. The flag's other job (history filtering) still
    /// applies to those user messages so they aren't sent to the LLM.
    private var showsSafetyVariant: Bool {
        message.isSafetyResource && !isUser
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if showsSafetyVariant {
                    safetyResourceBubble
                } else {
                    standardBubble
                }

                Text(formatTime(message.timestamp))
                    .font(AppFonts.caption(11))
                    .foregroundColor(AppColors.textMuted)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    /// The normal user/assistant bubble — extracted so the safety variant
    /// can swap in without duplicating the entire body.
    private var standardBubble: some View {
        Text(message.content)
            .font(AppFonts.body(15))
            .foregroundColor(isUser ? AppColors.userBubbleText : AppColors.aiBubbleText)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isUser
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                      )
                    : AnyShapeStyle(AppColors.aiBubble)
            )
            .cornerRadius(18)
            .overlay(
                !isUser
                    ? RoundedRectangle(cornerRadius: 18)
                        .stroke(AppColors.aiBubbleBorder, lineWidth: 1)
                    : nil
            )
            .contextMenu {
                Button {
                    // Coach replies often quote PII back to the user. Cap the
                    // pasteboard lifetime to 60s and keep it local-device so
                    // it never lands in iCloud Universal Clipboard.
                    UIPasteboard.general.setItems(
                        [[UIPasteboard.typeAutomatic: message.content]],
                        options: [
                            .expirationDate: Date().addingTimeInterval(60),
                            .localOnly: true
                        ]
                    )
                } label: {
                    Label("Copy Message", systemImage: "doc.on.doc")
                }
            }
    }

    /// Distinct rendering for messages flagged `isSafetyResource` (the
    /// hardcoded `SafeResourceCopy.message()` returned by the crisis gate
    /// in either ChatManager.send or DailyRecapGenerator). Mirrors the
    /// `safetyResourceCard` variant in CheckInDetailView so the chat
    /// surface and the recap surface look consistent when the user is
    /// being shown crisis resources rather than a generated reply.
    ///
    /// Differences from `standardBubble`:
    ///   1. "Support resources" header (coral) — VoiceOver announces this
    ///      as the framing instead of the standard bubble framing.
    ///   2. Tappable `Link` to `SafeResourceCopy.actionURL()`. Pre-fix
    ///      the URL was plain text inside the message body; auto-link
    ///      recognition is unreliable and the link wasn't keyboard /
    ///      VoiceOver focusable.
    ///   3. Coral-tinted background with stroke for visual distinction
    ///      across all 5 themes.
    ///   4. Container `accessibilityLabel` overrides to "Support resources"
    ///      so screen readers don't say "Message from assistant" for a
    ///      crisis-route reply.
    private var safetyResourceBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header + body grouped into a single a11y element so
            // VoiceOver announces "Support resources, <body>" on first
            // focus instead of fragmenting across header → body → Link
            // (BUG-04 from chat-bubble QA pass). Link stays OUTSIDE
            // this group as a discrete focusable action.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.coral)
                        .accessibilityHidden(true)
                    Text("Support resources")
                        .font(AppFonts.bodyMedium(13))
                        .foregroundColor(AppColors.coral)
                }

                Text(message.content)
                    .font(AppFonts.body(15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)

            Link(destination: SafeResourceCopy.actionURL()) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                    Text(SafeResourceCopy.findHelplineLabel())
                        .font(AppFonts.bodyMedium(13))
                }
                .foregroundColor(AppColors.coral)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppColors.coral.opacity(0.1))
                .cornerRadius(12)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Find a helpline")
            .accessibilityHint("Opens findahelpline.com in your browser")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColors.coral.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AppColors.coral.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(as: "h:mm a")
    }
}
