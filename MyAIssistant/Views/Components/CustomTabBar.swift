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
        .padding(.top, 12)
        .padding(.bottom, 8)
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
                        .font(AppFonts.heading(22))

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
