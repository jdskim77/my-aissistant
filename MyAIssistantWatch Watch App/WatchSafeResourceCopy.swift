import Foundation

/// Watch-target port of `SafeResourceCopy`. Hardcoded localized safety
/// message body + tappable hotline URL. Never LLM-generated.
///
/// Mirrors the iOS file's invariant: every regional branch must mention a
/// real, currently-operating resource AND include findahelpline.com as
/// fallback. Adding language-specific hotline numbers requires manual
/// verification. Conservative-fabrication policy: when we don't have a
/// validated number for a locale, return the international directory only.
enum WatchSafeResourceCopy {

    /// The visible body of the safety reply on watch chat.
    /// `detectedLanguage` (when non-nil) takes precedence over `Locale.current`
    /// — the watch's iOS counterpart added this for users typing in
    /// Japanese on en-US devices etc. Watch follows the same pattern.
    static func message(
        for locale: Locale = .current,
        detectedLanguage: String? = nil
    ) -> String {
        let language = detectedLanguage
            ?? locale.language.languageCode?.identifier
            ?? "en"
        let prefix = prefixSentence(language: language)
        let hotline = hotlineLine(for: locale, language: language)
        let joiner = (language == "zh" || language == "ja") ? "" : " "
        return prefix + joiner + hotline
    }

    /// URL the user is routed to when they tap the safety link.
    static func actionURL() -> URL {
        URL(string: "https://findahelpline.com")!
    }

    /// Localized "Find a helpline" button label.
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

    // MARK: - Localized prefix

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
                break
            }
        }
        return internationalFallback(language: language)
    }

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
