import SwiftUI

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last updated: April 1, 2026")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)

                section("What We Collect") {
                    """
                    Thrivn collects and stores the following data locally on your device:

                    • Tasks, check-ins, and schedule data you create
                    • Chat conversation history with the AI assistant
                    • App usage metrics (message counts, check-in counts) for free tier limits
                    • Calendar events you choose to sync from Apple Calendar or Google Calendar

                    This data is stored in your device's local database and is not transmitted to our servers.
                    """
                }

                section("AI Processing") {
                    """
                    When you use the AI assistant, your messages and schedule context are sent to Anthropic's API \
                    (Claude) for processing. Anthropic's privacy policy governs how they handle this data. \
                    We do not store your conversations on any server — they exist only on your device.

                    If you provide your own API key, requests go directly from your device to Anthropic. \
                    We never see or store your API key on our servers — it is stored in your device's secure Keychain.
                    """
                }

                section("Calendar Access") {
                    """
                    If you connect Apple Calendar, we use EventKit to read and write events locally. \
                    Calendar data never leaves your device except through Apple's own sync.

                    If you connect Google Calendar, we use OAuth 2.0 to access your calendar via Google's API. \
                    Your Google tokens are stored in your device's Keychain and are never shared.
                    """
                }

                section("Analytics & Tracking") {
                    """
                    Thrivn does not include any third-party analytics, advertising SDKs, or tracking libraries. \
                    We do not collect device identifiers, IP addresses, or location data.
                    """
                }

                section("Data Storage") {
                    """
                    All your data is stored locally on your device using Apple's SwiftData framework. \
                    If you use iCloud backup, your app data may be included in your backup per your device settings. \
                    You can delete all app data by uninstalling the app.
                    """
                }

                section("Children's Privacy") {
                    """
                    Thrivn is not directed at children under 13. We do not knowingly collect \
                    data from children.
                    """
                }

                section("Changes to This Policy") {
                    """
                    We may update this policy from time to time. The "Last updated" date at the top \
                    reflects the most recent revision. Continued use of the app constitutes acceptance \
                    of any changes.
                    """
                }

                section("Contact") {
                    """
                    For questions about this privacy policy, contact us at support@myaissistant.app.
                    """
                }
            }
            .padding(20)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)
            Text(content())
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .lineSpacing(4)
        }
    }
}

// MARK: - Terms of Service

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Last updated: April 1, 2026")
                    .font(AppFonts.caption(12))
                    .foregroundColor(AppColors.textMuted)

                section("Acceptance") {
                    """
                    By using Thrivn, you agree to these Terms of Service. If you do not agree, \
                    do not use the app.
                    """
                }

                section("Description of Service") {
                    """
                    Thrivn is a personal productivity app that provides AI-powered scheduling, \
                    check-ins, pattern tracking, and an AI chat assistant. The AI features are powered \
                    by third-party services (Anthropic Claude) and their availability depends on those services.
                    """
                }

                section("Subscriptions") {
                    """
                    Some features require a paid subscription. Subscriptions are billed through Apple's \
                    App Store and are subject to Apple's terms.

                    • Payment is charged to your Apple ID account at confirmation of purchase.
                    • Subscriptions automatically renew unless canceled at least 24 hours before \
                    the end of the current billing period.
                    • You can manage and cancel subscriptions in your device's Settings > Apple ID > \
                    Subscriptions.
                    • No refunds are provided for partial subscription periods.
                    """
                }

                section("API Keys") {
                    """
                    If you provide your own API key (Anthropic or OpenAI), you are responsible for \
                    any charges incurred on your API account. We are not responsible for API costs \
                    resulting from your use of the app.
                    """
                }

                section("AI-Generated Content") {
                    """
                    The AI assistant may generate incorrect, incomplete, or inappropriate content. \
                    AI responses are for informational purposes only and should not be relied upon \
                    for medical, legal, financial, or other professional advice. You are responsible \
                    for verifying any information provided by the AI.
                    """
                }

                section("Limitation of Liability") {
                    """
                    Thrivn is provided "as is" without warranty. We are not liable for any \
                    damages arising from your use of the app, including data loss, missed appointments, \
                    or reliance on AI-generated content.
                    """
                }

                section("Contact") {
                    """
                    For questions about these terms, contact us at support@myaissistant.app.
                    """
                }
            }
            .padding(20)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFonts.heading(16))
                .foregroundColor(AppColors.textPrimary)
            Text(content())
                .font(AppFonts.body(14))
                .foregroundColor(AppColors.textSecondary)
                .lineSpacing(4)
        }
    }
}
