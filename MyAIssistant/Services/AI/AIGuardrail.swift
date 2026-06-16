import Foundation

/// Single visible preflight path for every LLM call that forwards user
/// free-text. Wraps `CrisisClassifier` so "did you remember to gate this
/// surface?" has one answer: "did you go through `AIGuardrail.preflight`?"
///
/// Why this exists: the chat path was gated, the recap path was gated,
/// the watch chat path was gated — but `NLTaskParserView` was sending
/// user-typed strings straight to Anthropic with no precheck. That kind
/// of edge drift is exactly what this utility prevents. Every site that
/// passes user-supplied text to a provider goes through here.
///
/// Policy:
///  - **Always gates.** The default classifier is non-nil (`defaultClassifier`),
///    so a caller cannot accidentally skip the check by passing nil.
///    Tests can inject an alternate classifier via the parameter.
///  - **Side-effect light.** Emits a log + breadcrumb on block so the
///    route is traceable. Latch updates / message persistence belong to
///    each caller — their persistence shapes differ.
///  - **Returns localized safety message.** `SafeResourceCopy.message`
///    receives `evaluation.detectedLanguage`, so a Spanish-typed crisis
///    on an English-locale device gets Spanish copy.
enum AIGuardrail {

    /// Result of a preflight evaluation.
    enum Outcome: Equatable {
        /// Safe to forward to the LLM.
        case proceed
        /// Do not call the LLM. Render `safetyMessage` to the user instead.
        /// `evaluation` is included so the caller can persist the
        /// matched-language and trigger any caller-specific bookkeeping
        /// (per-day latch, breadcrumbs with extra context, etc.).
        case block(safetyMessage: String, evaluation: CrisisEvaluation)
    }

    /// Shared default classifier. Cheap to instantiate (patterns are
    /// compiled once in `init`), but reusing one instance avoids the
    /// regex-compile cost on hot paths like the recap iterator.
    static let defaultClassifier: CrisisClassifier = KeywordCrisisClassifier()

    /// Gate a single user-typed string before it reaches the model.
    ///
    /// - Parameters:
    ///   - userText: the raw user input the call would forward.
    ///   - classifier: defaults to `defaultClassifier`. Override only
    ///     for tests (e.g. a stub that always flags) or when a future
    ///     CoreML classifier is DI-injected.
    ///   - callSite: short identifier surfaced in logs ("chat",
    ///     "recap", "task-parser", "watch-chat"). Makes a production
    ///     safety route traceable to its origin without grepping
    ///     timestamps.
    static func preflight(
        userText: String,
        classifier: CrisisClassifier = defaultClassifier,
        callSite: String
    ) -> Outcome {
        let evaluation = classifier.evaluate(userText)
        guard evaluation.isCrisis else { return .proceed }
        let message = SafeResourceCopy.message(detectedLanguage: evaluation.detectedLanguage)
        AppLogger.ai.notice("AIGuardrail blocked LLM call — site=\(callSite, privacy: .public)")
        Breadcrumb.add(category: "ai", message: "Guardrail blocked at \(callSite)")
        return .block(safetyMessage: message, evaluation: evaluation)
    }

    /// Multi-input variant for surfaces aggregating multiple user
    /// strings (e.g., recap iterating over the day's notes). First
    /// crisis match wins. Empty/whitespace strings are skipped before
    /// classifier invocation — no allocation, no log noise.
    static func preflight(
        userTexts: [String],
        classifier: CrisisClassifier = defaultClassifier,
        callSite: String
    ) -> Outcome {
        for text in userTexts where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch preflight(userText: text, classifier: classifier, callSite: callSite) {
            case .proceed:
                continue
            case .block(let message, let evaluation):
                return .block(safetyMessage: message, evaluation: evaluation)
            }
        }
        return .proceed
    }
}
