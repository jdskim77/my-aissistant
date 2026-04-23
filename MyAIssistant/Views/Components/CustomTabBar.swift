import SwiftUI

/// Tab order is **coach-first** by design. The coach is the spine per
/// CLAUDE.md Pillar 1 — burying it behind the old center "✦" button was
/// the Instagram-Compose pattern applied to the main product. Schedule
/// used to occupy slot 2 but has been absorbed into Today as Overdue /
/// Now&next / Tomorrow sections; a top-right calendar icon on Today
/// opens the full Schedule view as a sheet for week/month navigation.
enum Tab: Int, CaseIterable {
    case coach = 0
    case home = 1
    case compass = 2
    case settings = 3

    /// SF Symbol names. Coach uses `sparkles` — the flat tab-glyph
    /// counterpart to the gradient AIPresenceIcon that used to live in
    /// the center button. Keeps the brand mark's sparkle vocabulary.
    var icon: String {
        switch self {
        case .coach:    return "sparkles"
        case .home:     return "checklist"
        case .compass:  return "safari"
        case .settings: return "gearshape.fill"
        }
    }

    var selectedIcon: String {
        switch self {
        case .coach:    return "sparkles"
        case .home:     return "checklist"
        case .compass:  return "safari.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .coach:    return "Coach"
        case .home:     return "Today"
        case .compass:  return "Compass"
        case .settings: return "Settings"
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    /// Count of unreacted nudges delivered to the Coach tab. Drives the
    /// red badge on the Coach icon so the user can see at a glance that
    /// the coach has something waiting, without needing a push.
    var coachBadge: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            tabButton(for: .coach, badge: coachBadge)
            tabButton(for: .home)
            tabButton(for: .compass)
            tabButton(for: .settings)
        }
        .padding(.horizontal, 16)
        // Tight padding so icons sit ~4pt above the home indicator
        // region — matches Apple's native UITabBar proportions. User
        // report 2026-04-23 (2nd pass): "buttons have a lot of space
        // at the bottom, they should be very slightly lowered." The
        // prior 18/8 values left a visible gap between the labels
        // and the home indicator.
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(
            AppColors.surface
                .shadow(color: AppColors.textPrimary.opacity(0.06), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .contain)
    }

    private func tabButton(for tab: Tab, badge: Int = 0) -> some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? .none : .spring(response: 0.3)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                        // Fixed system size, not Dynamic Type scaled.
                        // Apple's own UITabBar keeps icons at a fixed
                        // optical size regardless of AX text settings;
                        // using AppFonts.heading(22) let the icon grow
                        // to 40pt+ at AX5 and overflow the ZStack frame,
                        // clipping the glyph (QA BUG-07).
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 28, height: 28)

                    if badge > 0 {
                        // On-accent token (theme-aware) instead of
                        // hardcoded white: High Contrast / Twilight
                        // themes pair coral with a different foreground.
                        // Fixes BUG-07.
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(AppFonts.label(11))
                            .foregroundColor(AppColors.surface)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(AppColors.coral))
                            .offset(x: 8, y: -6)
                    }
                }

                Text(tab.label)
                    .font(AppFonts.caption(11))
                    // Single line with truncation — shrinking below
                    // ~11pt breaks HIG tab-label floor / WCAG
                    // readability. At AX sizes labels tail-truncate
                    // rather than scaling sub-minimum; users who
                    // need larger type get the system modal tab bar.
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundColor(selectedTab == tab ? AppColors.accent : AppColors.textMuted)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        // Composite label so the badge count is announced alongside the
        // tab name. The prior `accessibilityLabel(tab.label)` on the
        // Button overrode the badge's inner label, hiding the count
        // from VoiceOver. Fixes BUG-13.
        .accessibilityLabel(accessibilityLabel(for: tab, badge: badge))
        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
    }

    private func accessibilityLabel(for tab: Tab, badge: Int) -> String {
        guard badge > 0 else { return tab.label }
        let suffix = badge == 1 ? "1 unread nudge" : "\(badge) unread nudges"
        return "\(tab.label), \(suffix)"
    }
}
