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
    /// Localized per the languages the on-device crisis classifier covers
    /// (en/es/pt/zh/ja) so a flagged user gets safety copy in their own
    /// language. Hotline lines remain the verified English-region set
    /// (US/CA/GB/IE/AU/NZ) — adding language-specific hotline numbers
    /// requires native-language verification AND ongoing checks that
    /// numbers are currently-operating, which is a manual process.
    /// Non-English users in unmapped regions receive a localized
    /// "visit findahelpline.com" fallback rather than a fabricated number.
    ///
    /// `detectedLanguage` (when non-nil) takes precedence over `locale`
    /// for the prefix language. This solves the "user types Japanese on
    /// en-US device" gap — the classifier knows what language flagged,
    /// `Locale.current` doesn't. Callers that have access to a
    /// `CrisisEvaluation` should pass `evaluation.detectedLanguage`.
    static func message(
        for locale: Locale = .current,
        detectedLanguage: String? = nil
    ) -> String {
        let language = detectedLanguage
            ?? locale.language.languageCode?.identifier
            ?? "en"
        let prefix = prefixSentence(language: language)
        let hotline = hotlineLine(for: locale, language: language)
        // CJK languages don't use a leading ASCII space between sentences.
        // Concatenate without a space joiner for zh/ja so the visual
        // rhythm matches native typography (BUG-04 from the safety-copy
        // QA pass).
        let joiner = (language == "zh" || language == "ja") ? "" : " "
        return prefix + joiner + hotline
    }

    /// URL the user is routed to when they tap the nudge. `findahelpline.com`
    /// is a curated international directory that handles locale mapping
    /// server-side — a stable deep-link regardless of user region.
    static func actionURL(for locale: Locale = .current) -> URL {
        URL(string: "https://findahelpline.com")!
    }

    /// The primary action's visible label on the notification / banner.
    /// Localized to the languages the classifier covers. Callers that
    /// have access to a `CrisisEvaluation` should pass `detectedLanguage`
    /// for true text-language match; callers that don't (push notification
    /// payloads built before classifier ran) fall back to `Locale.current`.
    static func actionTitle(detectedLanguage: String? = nil, locale: Locale = .current) -> String {
        let language = detectedLanguage
            ?? locale.language.languageCode?.identifier
            ?? "en"
        switch language {
        case "es": return "Conseguir apoyo"
        case "pt": return "Obter apoio"
        case "zh": return "获取支持"
        case "ja": return "サポートを受ける"
        default:   return "Get support"
        }
    }

    /// "Find a helpline" — the inline link label inside chat bubble /
    /// check-in safety card. Same language map as `actionTitle`.
    static func findHelplineLabel(detectedLanguage: String? = nil, locale: Locale = .current) -> String {
        let language = detectedLanguage
            ?? locale.language.languageCode?.identifier
            ?? "en"
        switch language {
        case "es": return "Encontrar una línea de ayuda"
        case "pt": return "Encontrar uma linha de apoio"
        case "zh": return "查找求助热线"
        case "ja": return "相談窓口を探す"
        default:   return "Find a helpline"
        }
    }

    /// Non-user-facing identifier stored on the `Nudge` record so that
    /// delivery, analytics, and the coach-eval harness can distinguish a
    /// safety-route nudge from the rest.
    static let triggerContextKey = "safetyRoute"

    // MARK: - Localized prefix

    /// The opening "you're not alone" sentence, in the user's language.
    /// The crisis classifier matches in en/es/pt/zh/ja — same set localized
    /// here. Anything outside this set falls back to English.
    private static func prefixSentence(language: String) -> String {
        switch language {
        case "es":
            return "Si estás pasando por algo difícil, hay ayuda a solo una llamada o mensaje."
        case "pt":
            return "Se você está passando por algo difícil, há ajuda a uma ligação ou mensagem de distância."
        case "zh":
            return "如果你正在经历困难，帮助就在一通电话或一条信息之外。"
        case "ja":
            return "つらい思いをしているなら、電話やメッセージで助けを求められます。"
        default:
            return "If you're going through something heavy, help is one call or text away."
        }
    }

    // MARK: - Region mapping

    /// Region-specific hotline line appended to the message prefix. Every
    /// branch MUST mention a real, currently-operating resource and include
    /// findahelpline.com as fallback. When a region is unknown or unmapped,
    /// we return the international-only line **localized to the user's
    /// language** — so a Japanese user whose check-in note flags 死にたい
    /// gets the prefix in Japanese and the "visit findahelpline.com" line
    /// in Japanese, rather than English on top of Japanese.
    private static func hotlineLine(for locale: Locale, language: String) -> String {
        if let region = locale.region?.identifier {
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
                break  // fall through to localized international fallback
            }
        }
        // Unmapped region — return the international directory fallback in
        // the user's language. Adding a region-specific hotline for any
        // non-English locale requires manual verification of the number,
        // its current operating status, and SMS/voice availability.
        return internationalFallback(language: language)
    }

    /// "Visit findahelpline.com for help wherever you are." in each
    /// language the classifier covers.
    private static func internationalFallback(language: String) -> String {
        switch language {
        case "es":
            return "Visita findahelpline.com para encontrar ayuda donde estés."
        case "pt":
            return "Visite findahelpline.com para encontrar ajuda onde estiver."
        case "zh":
            return "请访问 findahelpline.com 寻求帮助。"
        case "ja":
            return "findahelpline.com から、お住まいの地域の支援先を探せます。"
        default:
            return "Visit findahelpline.com for help wherever you are."
        }
    }
}
