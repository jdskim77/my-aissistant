#if os(watchOS)
import SwiftUI
import WatchConnectivity
import AppIntents

@main
struct MyAIssistantWatchApp: App {
    private var connectivityManager = WatchConnectivityManager.shared
    @State private var selectedTab: WatchTab = .tasks
    @State private var showVoiceChat = false
    @State private var showAddTask = false

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                // Tab 1: Today — vertical progress bars + inline next row +
                // AI pill at the bottom. This is the primary home screen.
                // The AI pill inside WatchTodayView is the sole add path.
                NavigationStack {
                    WatchTodayView(connectivity: connectivityManager)
                        // Voice-chat is reachable two ways: the WatchAIPill at
                        // the bottom of WatchTodayView (NavigationLink), and
                        // the AskAIIntent / Action Button which flips
                        // shouldOpenVoiceChat → showVoiceChat.
                        .navigationDestination(isPresented: $showVoiceChat) {
                            WatchVoiceChatView(connectivity: connectivityManager)
                        }
                        .navigationDestination(isPresented: $showAddTask) {
                            WatchAddTaskView(connectivity: connectivityManager)
                        }
                        .navigationDestination(for: WatchScheduleData.WatchTask.self) { task in
                            WatchTaskDetailView(task: task, connectivity: connectivityManager)
                        }
                }
                .tag(WatchTab.tasks)

                // Tab 2: Quick Check-In
                WatchQuickCheckInView(connectivity: connectivityManager)
                    .tag(WatchTab.checkIn)
            }
            .tabViewStyle(.page)
            .onChange(of: connectivityManager.shouldOpenVoiceChat) { _, shouldOpen in
                if shouldOpen {
                    selectedTab = .tasks
                    showVoiceChat = true
                    connectivityManager.shouldOpenVoiceChat = false
                }
            }
            .onOpenURL { url in
                if url.scheme == "myaissistant" && url.host == "voice" {
                    selectedTab = .tasks
                    showVoiceChat = true
                }
            }
        }
    }

    enum WatchTab {
        case tasks, checkIn
    }
}

// MARK: - Action Button Intent

struct AskAIIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask AI Assistant"
    static var description: IntentDescription = "Start a voice conversation with your AI assistant."
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            WatchConnectivityManager.shared.shouldOpenVoiceChat = true
        }
        return .result()
    }
}

struct AIShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAIIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Hey \(.applicationName)"
            ],
            shortTitle: "Ask AI",
            systemImageName: "mic.circle.fill"
        )
    }
}

#else

// iOS fallback stub: lets the target link when xcodebuild is invoked with
// `-sdk iphonesimulator` (which overrides the target's watchOS SDK). This
// code is never executed — it only satisfies the linker's _main requirement.
import SwiftUI

@main
struct MyAIssistantWatchAppiOSStub: App {
    var body: some Scene {
        WindowGroup { EmptyView() }
    }
}

#endif
