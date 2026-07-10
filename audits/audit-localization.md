# Audit — Localization readiness
**Run:** /overnight 2026-05-04 pass 2

## Headline

**The app is English-only with no localization infrastructure.**

| Metric | Count |
|---|--:|
| Hardcoded `Text("...")` strings (English) in Views | **364** |
| `LocalizedStringKey` / `NSLocalizedString` uses | 0 |
| `String(localized:...)` uses | 0 |
| `.localized` string extensions | 0 |
| `Localizable.strings` files | none |
| `.lproj` directories | none |

## Implication

Adding a second language (or just preparing for App Store reviewer scrutiny on i18n) is a multi-day effort. The 364 hardcoded strings are the visible tip — comments, button labels, error messages, alert dialogs, accessibility labels, system prompts, and check-in prompts all need to be extracted.

## Strategy options

### Option A — accept English-only for v1 ship
**Recommendation if launch is imminent.** App Store accepts English-only apps. Document the limitation. Don't pretend i18n exists.

**Cost:** zero. Add a one-line `App Store description` note: "Currently English only. More languages coming."

### Option B — Extract to `String(localized:)` now, ship still English
Convert the 364 sites to `String(localized: "...")` form. No `.strings` file yet, but the strings are now extractable via `xcstringstool` for future translation.

**Cost:** ~6-8h mechanical work. Pure additive — does not change visible behavior. Lays the foundation.

### Option C — Add Spanish / Portuguese / German / Japanese / Chinese
Mental health apps that ship in only English miss large markets. The crisis classifier already covers Spanish, Portuguese, Chinese, Japanese (per `KeywordCrisisClassifier.swift`) — the domain assumption is multilingual users exist.

**Cost:** Option B + actual translation per language + native review. ~2-3 weeks of human translator time + QA.

## What's harder than it looks

### Day-staged greeting copy (AIPromptBuilder)

The day-by-day stage instructions are inline strings in the system prompt:

```
case 1: stageInstructions = "This is the user's FIRST DAY..."
case 2: stageInstructions = "Day 2. Focus on being practically helpful..."
```

These instructions are sent TO Claude, not shown to the user — but Claude is instructed in English. To support a Spanish user end-to-end:
- The user's UI strings need translation.
- The system prompt instructs Claude to respond in the user's language ("respond in the user's primary language") — already a common LLM pattern.
- The crisis classifier already handles the input side.
- The hardcoded `SafeResourceCopy.message()` is English-only with hotline numbers — would need locale-specific variants.

Per the existing skill `marketing-copy` and the `coaching-philosophy` skill, the *tone* of coach copy is hard to translate without losing voice. Mechanical translation will produce stilted Spanish/Japanese coach output. Plan for native-speaker tone review per language.

### SafeResourceCopy hotline numbers

[SafeResourceCopy.swift](MyAIssistant/Services/SafeResourceCopy.swift) provides locale-aware hotline numbers per region. The function shape supports localization but the message body is currently English-only. **This is the highest-priority i18n target** — a non-English speaker in crisis needs the safety message in their language.

**Cost:** ~2h per supported locale. Should ship locale-specific copy for any language the app explicitly supports.

## Findings ranked

### F1. (Strategic) — No i18n decision is documented
The codebase reads as if "we'll do i18n later." For an indie app, that's a defensible choice. But it should be explicit. **Action:** add a one-paragraph i18n stance to `CLAUDE.md` (or a `STRATEGY.md`).

### F2. (Medium) — `SafeResourceCopy.message()` is English-only
For a wellness app with multilingual crisis-classifier coverage, having English-only safety copy is an inconsistency. Anyone whose check-in note matches a Spanish/Portuguese/CJK pattern gets routed to safety… in English.

**Action:** make `SafeResourceCopy.message(for: Locale)` actually return locale-specific copy, not just locale-specific hotline numbers. ~3-4h covering en/es/pt/zh/ja.

### F3. (Low) — UI strings use `Text("...")` directly
The 364 hardcoded strings will be a 1-week refactor when i18n becomes a priority. Doing it now (Option B) is cheap insurance against a panicked refactor later.

### F4. (Low) — No date/number/currency localization
The app uses `formattedToday()` with a hardcoded English date format in `AIPromptBuilder.swift`. Numbers (counts, percentages) should already be locale-respecting via SwiftUI's default formatters, but worth verifying any custom number formatting.

## Recommended next step

If launch is imminent: **Option A** (accept English-only, document it).

If launch is 4+ weeks out: **Option B** + **F2** (extract strings + ship multilingual safety copy). ~10h of mechanical work, future-proofs the product.

If global launch is in scope: **Option C** with prioritized languages (Spanish + Portuguese cover major Latin American markets where mental-health stigma is high; Japanese for an upmarket niche). Plan for translator + native QA.
