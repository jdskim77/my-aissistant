import SwiftUI

@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: AppConstants.appThemeKey)
            themeID = UUID()
        }
    }

    /// Changes on every theme switch; used with `.id()` to force full re-render.
    var themeID = UUID()

    var currentTheme: ColorTheme {
        Self.theme(for: selectedTheme)
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: AppConstants.appThemeKey) ?? ""
        // Indigo is the brand-default theme for fresh installs.
        // Existing users keep whatever they had selected (rawValue lookup).
        self.selectedTheme = AppTheme(rawValue: saved) ?? .indigo
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
    }

    // MARK: - Theme Definitions

    static func theme(for appTheme: AppTheme) -> ColorTheme {
        switch appTheme {
        case .indigo: return indigo
        case .natural: return natural
        case .ocean: return ocean
        case .paper: return paper
        case .accessible: return accessible
        case .midnight: return midnight
        case .twilight: return twilight
        case .slate: return slate
        case .accessibleDark: return accessibleDark
        }
    }

    // MARK: - 0. Indigo (Brand Default — Thoughtful AI Identity)
    // Deep indigo signals "intelligent + introspective" — the same color
    // family used by Anthropic Claude, Linear, Vercel, and Perplexity.
    // Distinct from the green/blue wellness category, this is Thrivn's
    // signature visual identity. Pairs with the ThrivnCompassMark and
    // matches the indigo-blue tones in the Mind/Body/Heart Venn logo.

    private static let indigo = ColorTheme(
        background: Color(hex: "F8F7FB"),     // Soft lavender-tinted white
        surface: Color.white,
        card: Color(hex: "FDFCFE"),           // Brightest paper
        border: Color(hex: "E5E2EE"),         // Subtle indigo-tinted border
        accent: Color(hex: "4F46E5"),         // indigo-600 — primary brand color
        accentWarm: Color(hex: "6366F1"),     // indigo-500 — slightly lighter for emphasis
        accentLight: Color(hex: "EEF2FF"),    // indigo-50 — very subtle backgrounds
        gold: Color(hex: "D97706"),           // amber-600 — distinct from accent
        coral: Color(hex: "DC2626"),          // red-600
        skyBlue: Color(hex: "0284C7"),        // sky-600
        textPrimary: Color(hex: "1E1B2E"),    // Deep indigo-tinted ink (not pure black)
        textSecondary: Color(hex: "4B4862"),  // Muted indigo-gray
        textMuted: Color(hex: "7C7896"),      // Light indigo-gray
        morning: Color(hex: "F59E0B"),        // amber
        noon: Color(hex: "10B981"),           // emerald
        afternoon: Color(hex: "0284C7"),      // sky-600
        night: Color(hex: "7C3AED"),          // violet-600 (close to brand)
        overdueRed: Color(hex: "DC2626"),
        overdueBg: Color(hex: "FEF2F2"),
        completionGreen: Color(hex: "059669"),// emerald-600
        userBubbleText: Color.white,
        aiBubble: Color.white,
        aiBubbleText: Color(hex: "1E1B2E"),
        aiBubbleBorder: Color(hex: "E5E2EE"),
        checkboxHigh: Color(hex: "DC2626"),
        checkboxMedium: Color(hex: "D97706"),
        checkboxLow: Color(hex: "4F46E5"),    // Brand indigo for low priority
        error: Color(hex: "DC2626"),
        errorBg: Color(hex: "FEF2F2"),
        warning: Color(hex: "D97706"),
        warningBg: Color(hex: "FFFBEB"),
        success: Color(hex: "059669"),
        successBg: Color(hex: "ECFDF5"),
        disabled: Color(hex: "D6D3E5"),
        textDisabled: Color(hex: "9F9BB5")
    )

    // MARK: - 1. Natural (Improved Current)

    private static let natural = ColorTheme(
        background: Color(hex: "F8F5F0"),
        surface: Color.white,
        card: Color(hex: "FFFEFB"),
        border: Color(hex: "E8E2D9"),
        accent: Color(hex: "2D5016"),
        accentWarm: Color(hex: "4A7C2F"),
        accentLight: Color(hex: "E8F0E0"),
        gold: Color(hex: "B8860B"),
        coral: Color(hex: "C94B2B"),
        skyBlue: Color(hex: "1A5276"),
        textPrimary: Color(hex: "1A1A14"),
        textSecondary: Color(hex: "544E3F"),
        textMuted: Color(hex: "6E6860"),
        morning: Color(hex: "FF9500"),
        noon: Color(hex: "34C759"),
        afternoon: Color(hex: "007AFF"),
        night: Color(hex: "5856D6"),
        overdueRed: Color(hex: "D32F2F"),
        overdueBg: Color(hex: "FDEDED"),
        completionGreen: Color(hex: "34A853"),
        userBubbleText: Color.white,
        aiBubble: Color.white,
        aiBubbleText: Color(hex: "1A1A14"),
        aiBubbleBorder: Color(hex: "E8E2D9"),
        checkboxHigh: Color(hex: "D32F2F"),
        checkboxMedium: Color(hex: "E8860B"),
        checkboxLow: Color(hex: "1A5276"),
        error: Color(hex: "D32F2F"),
        errorBg: Color(hex: "FDEDED"),
        warning: Color(hex: "E8860B"),
        warningBg: Color(hex: "FFF8E1"),
        success: Color(hex: "34A853"),
        successBg: Color(hex: "E8F5E9"),
        disabled: Color(hex: "C4BEB5"),
        textDisabled: Color(hex: "9E9890")
    )

    // MARK: - 2. Ocean

    private static let ocean = ColorTheme(
        background: Color(hex: "F0F4F8"),
        surface: Color.white,
        card: Color(hex: "F8FAFC"),
        border: Color(hex: "D1D9E6"),
        accent: Color(hex: "1B6B93"),
        accentWarm: Color(hex: "2E96C9"),
        accentLight: Color(hex: "E1F0FA"),
        gold: Color(hex: "C07D10"),
        coral: Color(hex: "C94B2B"),
        skyBlue: Color(hex: "1B6B93"),
        textPrimary: Color(hex: "111827"),
        textSecondary: Color(hex: "4B5563"),
        textMuted: Color(hex: "6B7280"),
        morning: Color(hex: "F59E0B"),
        noon: Color(hex: "10B981"),
        afternoon: Color(hex: "3B82F6"),
        night: Color(hex: "8B5CF6"),
        overdueRed: Color(hex: "DC2626"),
        overdueBg: Color(hex: "FEF2F2"),
        completionGreen: Color(hex: "059669"),
        userBubbleText: Color.white,
        aiBubble: Color(hex: "F8FAFC"),
        aiBubbleText: Color(hex: "111827"),
        aiBubbleBorder: Color(hex: "D1D9E6"),
        checkboxHigh: Color(hex: "DC2626"),
        checkboxMedium: Color(hex: "F59E0B"),
        checkboxLow: Color(hex: "1B6B93"),
        error: Color(hex: "DC2626"),
        errorBg: Color(hex: "FEF2F2"),
        warning: Color(hex: "F59E0B"),
        warningBg: Color(hex: "FFFBEB"),
        success: Color(hex: "059669"),
        successBg: Color(hex: "ECFDF5"),
        disabled: Color(hex: "C8CED6"),
        textDisabled: Color(hex: "9CA3AF")
    )

    // MARK: - 3. Paper (Editorial Cream & Sepia)
    // Inspired by iA Writer, Kindle Paperwhite, Bear, and Day One.
    // Warm cream background with sepia/burgundy accents — feels like
    // a notebook or hardback book. Pairs with Thrivn's reflective tone
    // (daily wisdom, check-ins, journaling). Cream is also gentler on
    // photosensitive eyes than pure white.

    private static let paper = ColorTheme(
        background: Color(hex: "F5EFE0"),     // Warm cream (Kindle-inspired)
        surface: Color(hex: "FBF6E9"),        // Lighter cream — like a page lifted from the stack
        card: Color(hex: "FFFAEC"),           // Brightest cream for foreground content
        border: Color(hex: "E0D5BD"),         // Soft sepia border
        accent: Color(hex: "8B3A2F"),         // Deep burgundy / sepia ink
        accentWarm: Color(hex: "A85C42"),     // Lighter burgundy / brick
        accentLight: Color(hex: "F0E2D0"),    // Very pale parchment
        gold: Color(hex: "B5894A"),           // Antique gold
        coral: Color(hex: "B84A2E"),          // Vermillion
        skyBlue: Color(hex: "4A6B7C"),        // Muted slate-blue (subtle, not modern)
        textPrimary: Color(hex: "2B1F14"),    // Dark coffee — softer than pure black
        textSecondary: Color(hex: "5C4A35"),  // Walnut
        textMuted: Color(hex: "8A7556"),      // Light sepia
        morning: Color(hex: "C77B30"),        // Burnt orange
        noon: Color(hex: "7A8C3A"),           // Olive
        afternoon: Color(hex: "4A6B7C"),      // Slate blue
        night: Color(hex: "5D4B7C"),          // Plum
        overdueRed: Color(hex: "A8321E"),     // Iron oxide red
        overdueBg: Color(hex: "F5E0D8"),
        completionGreen: Color(hex: "5A7A2E"),// Olive green
        userBubbleText: Color(hex: "FBF6E9"), // Cream on burgundy
        aiBubble: Color(hex: "FFFAEC"),
        aiBubbleText: Color(hex: "2B1F14"),
        aiBubbleBorder: Color(hex: "E0D5BD"),
        checkboxHigh: Color(hex: "A8321E"),
        checkboxMedium: Color(hex: "C77B30"),
        checkboxLow: Color(hex: "4A6B7C"),
        error: Color(hex: "A8321E"),
        errorBg: Color(hex: "F5E0D8"),
        warning: Color(hex: "C77B30"),
        warningBg: Color(hex: "F8EBD5"),
        success: Color(hex: "5A7A2E"),
        successBg: Color(hex: "EDF0DA"),
        disabled: Color(hex: "D4C8AE"),
        textDisabled: Color(hex: "A89878")
    )

    // MARK: - 4. Accessible (Colorblind-Friendly, WCAG AAA)

    private static let accessible = ColorTheme(
        background: Color.white,
        surface: Color(hex: "F5F5F5"),
        card: Color.white,
        border: Color(hex: "BDBDBD"),
        accent: Color(hex: "0052CC"),
        accentWarm: Color(hex: "0065FF"),
        accentLight: Color(hex: "DEEBFF"),
        gold: Color(hex: "E65100"),       // Orange (not gold — avoids yellow confusion)
        coral: Color(hex: "D84315"),      // Deep orange-red
        skyBlue: Color(hex: "0052CC"),
        textPrimary: Color.black,          // 21:1 on white
        textSecondary: Color(hex: "333333"), // 12.6:1 on white
        textMuted: Color(hex: "555555"),   // 7.5:1 on white (WCAG AAA)
        morning: Color(hex: "E65100"),
        noon: Color(hex: "0052CC"),
        afternoon: Color(hex: "1565C0"),
        night: Color(hex: "4A148C"),
        overdueRed: Color(hex: "B71C1C"),
        overdueBg: Color(hex: "FFEBEE"),
        completionGreen: Color(hex: "1565C0"),  // Blue not green — colorblind-safe
        userBubbleText: Color.white,
        aiBubble: Color(hex: "F5F5F5"),
        aiBubbleText: Color.black,
        aiBubbleBorder: Color(hex: "BDBDBD"),
        checkboxHigh: Color(hex: "D84315"),    // Orange
        checkboxMedium: Color(hex: "E65100"),  // Darker orange
        checkboxLow: Color(hex: "0052CC"),     // Blue
        error: Color(hex: "B71C1C"),
        errorBg: Color(hex: "FFEBEE"),
        warning: Color(hex: "E65100"),
        warningBg: Color(hex: "FFF3E0"),
        success: Color(hex: "1565C0"),         // Blue — colorblind-safe
        successBg: Color(hex: "E3F2FD"),
        disabled: Color(hex: "BDBDBD"),
        textDisabled: Color(hex: "9E9E9E")
    )

    // MARK: - 4. Midnight (OLED Dark)

    private static let midnight = ColorTheme(
        background: Color.black,
        surface: Color(hex: "111111"),
        card: Color(hex: "1A1A1A"),
        border: Color(hex: "2D2D2D"),
        accent: Color(hex: "5DB075"),
        accentWarm: Color(hex: "7BC794"),
        accentLight: Color(hex: "1A2E22"),
        gold: Color(hex: "D4A76A"),
        coral: Color(hex: "E57373"),
        skyBlue: Color(hex: "64B5F6"),
        textPrimary: Color(hex: "F0F0F0"),
        textSecondary: Color(hex: "A0A0A0"),
        textMuted: Color(hex: "707070"),
        morning: Color(hex: "FFB74D"),
        noon: Color(hex: "66BB6A"),
        afternoon: Color(hex: "64B5F6"),
        night: Color(hex: "B39DDB"),
        overdueRed: Color(hex: "EF5350"),
        overdueBg: Color(hex: "3D1515"),
        completionGreen: Color(hex: "66BB6A"),
        userBubbleText: Color.white,
        aiBubble: Color(hex: "1A1A1A"),
        aiBubbleText: Color(hex: "F0F0F0"),
        aiBubbleBorder: Color(hex: "2D2D2D"),
        checkboxHigh: Color(hex: "EF5350"),
        checkboxMedium: Color(hex: "FFB74D"),
        checkboxLow: Color(hex: "64B5F6"),
        error: Color(hex: "EF5350"),
        errorBg: Color(hex: "3D1515"),
        warning: Color(hex: "FFB74D"),
        warningBg: Color(hex: "3D2E15"),
        success: Color(hex: "66BB6A"),
        successBg: Color(hex: "1A2E1A"),
        disabled: Color(hex: "424242"),
        textDisabled: Color(hex: "616161")
    )

    // MARK: - 5. Twilight (Soft Dark)

    private static let twilight = ColorTheme(
        background: Color(hex: "1C1C1E"),
        surface: Color(hex: "2C2C2E"),
        card: Color(hex: "3A3A3C"),
        border: Color(hex: "48484A"),
        accent: Color(hex: "D4A76A"),
        accentWarm: Color(hex: "E0BD85"),
        accentLight: Color(hex: "3D3428"),
        gold: Color(hex: "E0BD85"),
        coral: Color(hex: "FF8A80"),
        skyBlue: Color(hex: "82B1FF"),
        textPrimary: Color(hex: "EEEEE8"),
        textSecondary: Color(hex: "A8A8A0"),
        textMuted: Color(hex: "787870"),
        morning: Color(hex: "FFB74D"),
        noon: Color(hex: "81C784"),
        afternoon: Color(hex: "82B1FF"),
        night: Color(hex: "CE93D8"),
        overdueRed: Color(hex: "FF5252"),
        overdueBg: Color(hex: "3D2020"),
        completionGreen: Color(hex: "81C784"),
        userBubbleText: Color.white,
        aiBubble: Color(hex: "3A3A3C"),
        aiBubbleText: Color(hex: "EEEEE8"),
        aiBubbleBorder: Color(hex: "48484A"),
        checkboxHigh: Color(hex: "FF5252"),
        checkboxMedium: Color(hex: "FFB74D"),
        checkboxLow: Color(hex: "82B1FF"),
        error: Color(hex: "FF5252"),
        errorBg: Color(hex: "3D2020"),
        warning: Color(hex: "FFB74D"),
        warningBg: Color(hex: "3D3020"),
        success: Color(hex: "81C784"),
        successBg: Color(hex: "1C2E1C"),
        disabled: Color(hex: "48484A"),
        textDisabled: Color(hex: "636366")
    )

    // MARK: - 6. Slate (Cool Blue-Gray Dark)
    // Inspired by Linear, Vercel, and Things 3 dark mode aesthetics.
    // Cool desaturated blue-gray surfaces with an indigo accent —
    // distinct from Midnight (warm-neutral OLED) and Twilight (warm gray).

    private static let slate = ColorTheme(
        background: Color(hex: "0F172A"),     // slate-900
        surface: Color(hex: "1E293B"),        // slate-800
        card: Color(hex: "263449"),           // slate-800 lifted
        border: Color(hex: "334155"),         // slate-700
        accent: Color(hex: "818CF8"),         // indigo-400
        accentWarm: Color(hex: "A5B4FC"),     // indigo-300 (lighter for emphasis on dark)
        accentLight: Color(hex: "1E1B4B"),    // indigo-950 (subtle backgrounds)
        gold: Color(hex: "FBBF24"),           // amber-400
        coral: Color(hex: "F87171"),          // red-400
        skyBlue: Color(hex: "38BDF8"),        // sky-400
        textPrimary: Color(hex: "F1F5F9"),    // slate-100
        textSecondary: Color(hex: "CBD5E1"),  // slate-300
        textMuted: Color(hex: "94A3B8"),      // slate-400
        morning: Color(hex: "FBBF24"),        // amber
        noon: Color(hex: "34D399"),           // emerald-400
        afternoon: Color(hex: "60A5FA"),      // blue-400
        night: Color(hex: "A78BFA"),          // violet-400
        overdueRed: Color(hex: "F87171"),
        overdueBg: Color(hex: "3F1F1F"),
        completionGreen: Color(hex: "34D399"),
        userBubbleText: Color.white,
        aiBubble: Color(hex: "263449"),
        aiBubbleText: Color(hex: "F1F5F9"),
        aiBubbleBorder: Color(hex: "334155"),
        checkboxHigh: Color(hex: "F87171"),
        checkboxMedium: Color(hex: "FBBF24"),
        checkboxLow: Color(hex: "60A5FA"),
        error: Color(hex: "F87171"),
        errorBg: Color(hex: "3F1F1F"),
        warning: Color(hex: "FBBF24"),
        warningBg: Color(hex: "3F2F1F"),
        success: Color(hex: "34D399"),
        successBg: Color(hex: "1F3F2F"),
        disabled: Color(hex: "334155"),
        textDisabled: Color(hex: "64748B")
    )

    // MARK: - 8. Accessible Dark (Colorblind-Friendly Dark Mode, WCAG AAA)
    // Dark counterpart to the Accessible theme. Same colorblind-safe palette
    // strategy (blue replaces green for success; orange + blue for priority)
    // but on a true black background. Designed for users who need both
    // colorblind support AND dark mode (e.g. light sensitivity, photophobia,
    // late-night use). Text colors meet WCAG AAA contrast on black.

    private static let accessibleDark = ColorTheme(
        background: Color.black,                  // True black for OLED + max contrast
        surface: Color(hex: "0F0F0F"),
        card: Color(hex: "1A1A1A"),
        border: Color(hex: "404040"),             // Lighter border for clear separation
        accent: Color(hex: "60A5FA"),             // Bright blue (replaces green for success)
        accentWarm: Color(hex: "93C5FD"),         // Lighter blue for emphasis
        accentLight: Color(hex: "1E3A5F"),
        gold: Color(hex: "FBBF24"),               // Amber (warnings/secondary — distinct from coral)
        coral: Color(hex: "FB923C"),              // Orange (urgent/high priority)
        skyBlue: Color(hex: "60A5FA"),
        textPrimary: Color(hex: "FFFFFF"),        // 21:1 on black
        textSecondary: Color(hex: "E5E5E5"),      // ~16:1 on black
        textMuted: Color(hex: "BBBBBB"),          // ~10:1 on black (WCAG AAA)
        morning: Color(hex: "FB923C"),            // Orange
        noon: Color(hex: "60A5FA"),               // Blue
        afternoon: Color(hex: "93C5FD"),          // Light blue
        night: Color(hex: "C4B5FD"),              // Light violet (distinguishable from blues)
        overdueRed: Color(hex: "F87171"),         // Bright red — distinguishable from orange
        overdueBg: Color(hex: "3F1F1F"),
        completionGreen: Color(hex: "60A5FA"),    // Blue not green — colorblind-safe
        userBubbleText: Color.white,
        aiBubble: Color(hex: "1A1A1A"),
        aiBubbleText: Color(hex: "FFFFFF"),
        aiBubbleBorder: Color(hex: "404040"),
        checkboxHigh: Color(hex: "F87171"),       // Red
        checkboxMedium: Color(hex: "FB923C"),     // Orange
        checkboxLow: Color(hex: "60A5FA"),        // Blue
        error: Color(hex: "F87171"),
        errorBg: Color(hex: "3F1F1F"),
        warning: Color(hex: "FB923C"),
        warningBg: Color(hex: "3F2F1F"),
        success: Color(hex: "60A5FA"),            // Blue not green
        successBg: Color(hex: "1F2F3F"),
        disabled: Color(hex: "404040"),
        textDisabled: Color(hex: "808080")
    )
}
