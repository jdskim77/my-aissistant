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
                        Text("\(badge)")
                            .font(AppFonts.label(11))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(AppColors.coral)
                            .cornerRadius(8)
                            .offset(x: 8, y: -6)
                            .accessibilityLabel("\(badge) unreacted nudges")
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
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
    }
}
