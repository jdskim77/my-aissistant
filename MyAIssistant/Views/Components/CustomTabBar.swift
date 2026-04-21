import SwiftUI

enum Tab: Int, CaseIterable {
    case home = 0
    case schedule = 1
    case compass = 2
    case settings = 3

    var icon: String {
        switch self {
        case .home: return "checklist"
        case .schedule: return "calendar"
        case .compass: return "safari"
        case .settings: return "gearshape.fill"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "checklist"
        case .schedule: return "calendar"
        case .compass: return "safari.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Today"
        case .schedule: return "Schedule"
        case .compass: return "Compass"
        case .settings: return "Settings"
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    let onAITap: () -> Void
    var scheduleBadge: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scales up to ~75pt at AX5 Dynamic Type, capped so it can't eat the tab
    /// bar. Icon stays a comfortable tap target on large-text users.
    @ScaledMetric(relativeTo: .title) private var aiIconBaseSize: CGFloat = 60

    var body: some View {
        HStack {
            tabButton(for: .home)
            tabButton(for: .schedule, badge: scheduleBadge)

            Spacer()
            aiCenterButton
            Spacer()

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
                    Image(systemName: tab.icon)
                        .font(AppFonts.heading(22))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(AppFonts.label(11))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(AppColors.coral)
                            .cornerRadius(8)
                            .offset(x: 8, y: -6)
                            .accessibilityLabel("\(badge) pending tasks")
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

    private var aiCenterButton: some View {
        let iconSize = min(aiIconBaseSize, 75)
        return Button {
            Haptics.medium()
            onAITap()
        } label: {
            AIPresenceIcon(size: iconSize)
                // Larger, softer shadow so the lift is visible past the
                // opaque tab-bar surface (a tight y:2 shadow gets absorbed).
                // Applied on the static puck — the tab bar doesn't animate
                // scale, so shadow stays anchored.
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .frame(width: iconSize, height: iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(y: -20)
        .accessibilityLabel("AI Assistant")
    }
}
