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
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .contain)
    }

    private func tabButton(for tab: Tab, badge: Int = 0) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                        .font(.system(size: 22))

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(AppColors.onAccent)
                            .frame(width: 16, height: 16)
                            .background(AppColors.coral)
                            .cornerRadius(8)
                            .offset(x: 8, y: -6)
                            .accessibilityLabel("\(badge) pending tasks")
                    }
                }

                Text(tab.label)
                    .font(AppFonts.caption(10))
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
        Button {
            Haptics.medium()
            onAITap()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentWarm],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: AppColors.accent.opacity(0.35), radius: 10, x: 0, y: 4)

                Image("ThrivnLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }
            .offset(y: -20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Assistant")
    }
}
