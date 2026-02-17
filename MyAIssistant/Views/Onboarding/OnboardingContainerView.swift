import SwiftUI
import SwiftData

struct OnboardingContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var currentPage = 0
    @Binding var onboardingComplete: Bool

    var body: some View {
        TabView(selection: $currentPage) {
            WelcomeView(onContinue: { currentPage = 1 })
                .tag(0)

            PermissionsView(onContinue: { currentPage = 2 })
                .tag(1)

            SubscriptionOfferView(onContinue: { currentPage = 3 })
                .tag(2)

            OnboardingCompleteView(onFinish: completeOnboarding)
                .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.3), value: currentPage)
        .ignoresSafeArea()
    }

    private func completeOnboarding() {
        // Create or update UserProfile
        let descriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(descriptor).first {
            profile.onboardingCompleted = true
        } else {
            let profile = UserProfile(onboardingCompleted: true)
            modelContext.insert(profile)
        }
        try? modelContext.save()

        withAnimation(.easeInOut(duration: 0.4)) {
            onboardingComplete = true
        }
    }
}
