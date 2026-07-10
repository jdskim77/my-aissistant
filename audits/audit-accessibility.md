# Audit — Accessibility + Dynamic Type
**Run:** /overnight 2026-05-04
**Scope:** all production `.swift` under `MyAIssistant/`.
**Method:** count + sample + read `AppFonts.swift`.

## Headline numbers

| Metric | Count | Read |
|---|--:|---|
| `Button {` sites | 199 | total interactive Button surface |
| `.accessibilityLabel(...)` uses | 129 | 65% labeled — but text-buttons auto-label, so real gap is smaller |
| `Image(systemName:)` (top-level) | 267 | total SF Symbols rendered |
| `.accessibilityHidden(true)` uses | 32 | 12% explicitly hidden — icon-with-adjacent-label patterns may double-announce |
| `.font(.system(size: N))` literals | 96 | hardcoded sizes — bypass Dynamic Type unless wrapped |
| `AppFonts.*` calls | 836 | 89% adoption — strong baseline |
| `@ScaledMetric` declarations | 1 | **very low** — non-text Dynamic Type scaling is under-covered |
| `accessibilityReduceMotion` checks | 16 | spot-checked — looks OK on the high-motion surfaces |

## Strong points

### S1. AppFonts wraps `UIFontMetrics.default.scaledValue`
[AppFonts.swift:13](MyAIssistant/Theme/AppFonts.swift#L13) → `static func scaled(_:)` calls `UIFontMetrics.default.scaledValue(for:)`. This means **every text using AppFonts.* respects iOS Dynamic Type AND the in-app TextSizeManager scale**. That's good architecture.

### S2. Custom `EnvironmentKey` DI pattern (not @EnvironmentObject)
Per CLAUDE.md, the project uses `@Environment(\.taskManager)` etc. with custom keys — correct iOS 17+ pattern. Avoids the `@EnvironmentObject`/`@Observable` mismatch trap.

### S3. Reduce Motion respected at high-animation surfaces
ChatView's mic pulse, BalancePulseCard's neutral pulse, ParticleAnimator — all read `accessibilityReduceMotion` from `@Environment` and gate spring/keyframe animations.

## Gaps — ranked by risk

### G1. (High) — 96 hardcoded `.font(.system(size: N))` calls
The 11% that bypass `AppFonts` won't scale with Dynamic Type. Per the rule: *"NEVER hardcode point sizes on text. Use SwiftUI dynamic text styles or `@ScaledMetric`."*

Locations clustered:
- `Views/Settings/TextSizeSettingsView.swift` — **intentional** (this view PREVIEWS sizes; leave alone).
- `Views/Settings/ThemePickerView.swift:30`
- `Views/Settings/SubscriptionView.swift:76, 155`
- `Views/Home/TodaysContextSheet.swift:138, 144, 196, 204, 215`
- (~80 more — full list via `grep -rEn '\.font\(\.system\(size:'`)

**Fix cost:** ~1.5h to convert all to `AppFonts.*`. Mostly mechanical.

### G2. (High) — `@ScaledMetric` used only once
Non-text values (icon sizes, fixed frame widths, padding) don't scale with Dynamic Type by default. Examples likely missing scaling:
- The 44×44pt action buttons in ChatView's input row
- Tab bar icon sizes (`.font(.system(size: 22, weight: .regular))` in CustomTabBar)
- Card padding values (14, 16, 20)

**Action:** survey fixed `frame(width:height:)` and `padding(N)` calls, identify which ones contain text or icons that should grow at AX5.

**Fix cost:** ~3h. Real visual work — needs device testing at AX5 to know what looks wrong.

### G3. (Medium) — 235 unhidden SF Symbols
267 `Image(systemName:)` − 32 `.accessibilityHidden(true)` = 235 icons that may announce themselves to VoiceOver.

Many are correctly auto-paired with adjacent text where the icon is decorative. But:
- Toolbar buttons with icon-only need `.accessibilityLabel` (not hidden).
- Icons inside Button labels with adjacent text should have `.accessibilityHidden(true)` so VoiceOver reads only the text label, not "checkmark, Mark complete".

**Action:** view-by-view audit. Sample 3 views (HomeView, ChatView, SettingsView) and tag each Image as: needs label / needs hidden / OK (auto-label from Button container).

**Fix cost:** ~2h.

### G4. (Medium) — Buttons with no `.accessibilityLabel`
65% of Button sites (129/199) have an explicit label. Some of the unlabeled ones are text-buttons that auto-label correctly. Some likely have icon-only or container patterns where VoiceOver gets garbled output.

**Action:** Run with VoiceOver, navigate every screen, transcribe the announcements. Flag any that says "Button" with no description, or describes the UI element instead of the action.

**Fix cost:** ~3h device-time.

### G5. (Medium) — Touch target size verification
Per the rule: *"Minimum 44×44pt for every interactive element."*

Several places use `Image(systemName:).font(...)` without an enclosing `frame(width: 44, height: 44)`. Some Buttons rely on `.frame(minHeight: 44)` only (height covered, width may not be).

**Action:** spot-check all `Button { Image... }` patterns. Especially:
- `Views/Chat/ChatView.swift` — context-aware action button (verified ≥44).
- `Views/Settings/APIKeySettingsView.swift` — show/hide key button.
- `Views/Components/CustomTabBar.swift` — tab buttons.

**Fix cost:** ~1.5h survey + small fixes.

### G6. (Low) — Color contrast under "Increase Contrast"
`AppColors.textMuted` and faded states (e.g. `.opacity(0.4)` patterns scattered across views) may fail WCAG AA contrast under "Increase Contrast" system setting.

**Action:** boot the app with Increase Contrast on and screenshot every state. Compare to baseline.

**Fix cost:** ~2h (slow due to manual screenshot pass).

### G7. (Low) — Decorative-image policy
Project uses SF Symbols heavily. The pattern "icon next to text" is everywhere. The `.accessibilityHidden(true)` count (32) suggests this isn't applied consistently. VoiceOver users may hear "(icon name), (button text)" duplication on many surfaces.

**Action:** establish a rule: icons inside Buttons/Labels with text get `.accessibilityHidden(true)` UNLESS the icon conveys unique meaning (status dot, badge).

## Recommended fix order

1. **G1** — `.font(.system(size:))` cleanup (~1.5h, mechanical).
2. **G3** — decorative-icon `.accessibilityHidden` pass on Home + Chat + Settings (~2h sampled).
3. **G2** — `@ScaledMetric` for icon/frame values that contain text or scale-relevant glyphs (~3h, needs device testing).
4. **G4** — Button label survey (~3h, needs VoiceOver session).
5. **G5** — touch-target audit (~1.5h).
6. **G6** + **G7** — opportunistic.

Total: **~13h of accessibility work** to get to "AX5-ready, VoiceOver-clean" state. Worth a dedicated week.
