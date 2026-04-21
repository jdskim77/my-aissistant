import Foundation

/// Hardcoded safe-messaging copy for the crisis-route nudge. **Never LLM-generated.**
///
/// When the on-device crisis classifier flags user free-text (latest check-in
/// notes or, later, chat transcripts), `NudgeEngine` routes a single safety-
/// resource nudge to the user and suppresses all other nudges for 24h. This
/// file owns the copy for that nudge.
///
/// Copy guidelines — per the `crisis-safety-protocols` skill and #chatsafe:
///
/// - Do NOT romanticize, minimize, sensationalize, or problem-solve the
///   user's state. Offer a path to human help.
/// - Do NOT promise privacy/anonymity that we don't control.
/// - Keep to ≤ 2 short sentences so it fits iOS notification preview.
/// - Name a concrete resource for the user's region. Include the international
///   fallback (findahelpline.com) as a safety net.
/// - Never generate via LLM — copy changes here require a human review gate.
///
/// Spec: §7.4. Region mapping is conservative — if we don't have a validated
/// hotline for a locale, we surface the international directory only.
enum SafeResourceCopy {

    /// The visible body of the safety nudge. ≤ 2 sentences.
    static func message(for locale: Locale = .current) -> String {
        let prefix = "If you're going through something heavy, help is one call or text away."
        return "\(prefix) \(hotlineLine(for: locale))"
    }

    /// URL the user is routed to when they tap the nudge. `findahelpline.com`
    /// is a curated international directory that handles locale mapping
    /// server-side — a stable deep-link regardless of user region.
    static func actionURL(for locale: Locale = .current) -> URL {
        URL(string: "https://findahelpline.com")!
    }

    /// The primary action's visible label on the notification / banner.
    static let actionTitle = "Get support"

    /// Non-user-facing identifier stored on the `Nudge` record so that
    /// delivery, analytics, and the coach-eval harness can distinguish a
    /// safety-route nudge from the rest.
    static let triggerContextKey = "safetyRoute"

    // MARK: - Region mapping

    /// Region-specific hotline line appended to the message prefix. Every
    /// branch MUST mention a real, currently-operating resource and include
    /// findahelpline.com as fallback. When a region is unknown or unmapped,
    /// we return the international-only line.
    private static func hotlineLine(for locale: Locale) -> String {
        guard let region = locale.region?.identifier else {
            return "Visit findahelpline.com for help wherever you are."
        }
        switch region {
        case "US":
            return "Call or text 988 (Suicide & Crisis Lifeline) or visit findahelpline.com."
        case "CA":
            return "Call or text 988 (Canada Suicide Crisis Helpline) or visit findahelpline.com."
        case "GB":
            return "Call 116 123 (Samaritans) or visit findahelpline.com."
        case "IE":
            return "Call 116 123 (Samaritans Ireland) or visit findahelpline.com."
        case "AU":
            return "Call 13 11 14 (Lifeline) or visit findahelpline.com."
        case "NZ":
            return "Call or text 1737 (Need to Talk?) or visit findahelpline.com."
        default:
            return "Visit findahelpline.com for help wherever you are."
        }
    }
}
