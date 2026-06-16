import XCTest
import SwiftUI
@testable import MyAIssistant

/// WCAG 2.2 contrast ratio harness for the color theme system.
///
/// **Standards (WCAG 2.2):**
/// - **AA body text:** 4.5:1 minimum contrast vs background.
/// - **AA large text** (≥18pt regular or ≥14pt bold): 3:1 minimum.
/// - **AA UI components / graphical objects:** 3:1 minimum.
/// - **AAA body text:** 7:1 (out of scope for this harness — AA is the goal).
///
/// Tested pairs are the canonical text-on-background combinations the app
/// uses heavily. Each pair is asserted across all 9 themes. A failure
/// here is a ship-blocker for the affected theme: a user on that theme
/// can't read the affected surface at AA level, which is a real
/// accessibility regression (and a potential App Store review issue).
///
/// Surfaces NOT covered by static-pair testing:
/// - Color-on-color blends (e.g. `coral.opacity(0.06)` over `card`):
///   needs alpha blending to compute. Future helper.
/// - Increase-Contrast / Reduce-Transparency system flags: out of scope.
/// - Per-pixel image contrast (icons): not testable from constants.
///
/// **Sample of the audit-themes-wcag finding (F2):** prior to this
/// harness, zero automated contrast verification existed. This test
/// catches regressions on every Cmd+U.
final class ColorContrastTests: XCTestCase {

    // MARK: - WCAG contrast computation

    /// Relative luminance per WCAG formula. Input is sRGB 0-1 components.
    /// Returns 0 (black) to 1 (white).
    private func relativeLuminance(_ color: Color) -> Double {
        let comps = sRGBComponents(of: color)
        func channel(_ c: Double) -> Double {
            // WCAG formula: c <= 0.03928 ? c/12.92 : ((c + 0.055)/1.055)^2.4
            if c <= 0.03928 { return c / 12.92 }
            return pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(comps.r) + 0.7152 * channel(comps.g) + 0.0722 * channel(comps.b)
    }

    /// Contrast ratio per WCAG: (lighter + 0.05) / (darker + 0.05).
    /// Range: 1.0 (no contrast) to 21.0 (black-on-white).
    private func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Extract sRGB 0-1 components from a SwiftUI Color via UIColor bridge.
    private func sRGBComponents(of color: Color) -> (r: Double, g: Double, b: Double) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    // MARK: - Critical pairs

    /// The canonical text-on-bg pairs that every theme must satisfy at AA.
    /// `(name, fg, bg)` — name appears in the assertion message so a
    /// failure log identifies which pair regressed without inspecting.
    private struct CriticalPair {
        let name: String
        let foreground: (ColorTheme) -> Color
        let background: (ColorTheme) -> Color
        let minRatio: Double  // 4.5 for body, 3.0 for large text / UI
    }

    private let criticalPairs: [CriticalPair] = [
        // Body text on the main backgrounds (4.5:1 AA).
        CriticalPair(name: "textPrimary on background",
                     foreground: \.textPrimary, background: \.background, minRatio: 4.5),
        CriticalPair(name: "textPrimary on surface",
                     foreground: \.textPrimary, background: \.surface, minRatio: 4.5),
        CriticalPair(name: "textPrimary on card",
                     foreground: \.textPrimary, background: \.card, minRatio: 4.5),
        CriticalPair(name: "textSecondary on surface",
                     foreground: \.textSecondary, background: \.surface, minRatio: 4.5),

        // Status/error UI components (3:1 minimum AA for graphical objects).
        CriticalPair(name: "error on errorBg",
                     foreground: \.error, background: \.errorBg, minRatio: 3.0),

        // Chat bubbles — user side renders on accent gradient; assistant on aiBubble.
        CriticalPair(name: "aiBubbleText on aiBubble",
                     foreground: \.aiBubbleText, background: \.aiBubble, minRatio: 4.5),

        // Accent-on-background for primary CTAs.
        CriticalPair(name: "accent on background",
                     foreground: \.accent, background: \.background, minRatio: 3.0)
    ]

    // MARK: - Tests

    /// Per-theme contrast assertions. A failure prints which theme + pair
    /// failed and the actual ratio, so the fix is targeted.
    func test_allThemes_meetWCAGContrastForCriticalPairs() {
        var failures: [String] = []

        for appTheme in AppTheme.allCases {
            let theme = ThemeManager.theme(for: appTheme)
            for pair in criticalPairs {
                let fg = pair.foreground(theme)
                let bg = pair.background(theme)
                let ratio = contrastRatio(fg, bg)
                if ratio < pair.minRatio {
                    failures.append(
                        String(format: "  %@ — %@: %.2f:1 (need %.1f:1)",
                               appTheme.rawValue, pair.name, ratio, pair.minRatio)
                    )
                }
            }
        }

        if !failures.isEmpty {
            XCTFail("WCAG contrast failures:\n" + failures.joined(separator: "\n"))
        }
    }

    /// Sanity test: black-on-white produces 21:1 (the maximum). Verifies
    /// the formula implementation is correct.
    func test_contrastFormula_blackOnWhite_yields21to1() {
        let ratio = contrastRatio(.black, .white)
        XCTAssertEqual(ratio, 21.0, accuracy: 0.01,
                       "Black-on-white must be 21:1 — formula bug if not.")
    }

    /// Sanity test: white-on-white produces 1:1.
    func test_contrastFormula_sameColor_yields1to1() {
        let ratio = contrastRatio(.white, .white)
        XCTAssertEqual(ratio, 1.0, accuracy: 0.01)
    }

    /// Property check: the order of foreground/background doesn't change
    /// the ratio (helper uses max/min internally, so this should hold).
    func test_contrastFormula_isCommutative() {
        let theme = ThemeManager.theme(for: .natural)
        let r1 = contrastRatio(theme.textPrimary, theme.background)
        let r2 = contrastRatio(theme.background, theme.textPrimary)
        XCTAssertEqual(r1, r2, accuracy: 0.001)
    }
}
