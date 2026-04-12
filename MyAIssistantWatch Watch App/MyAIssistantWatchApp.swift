#if os(watchOS)
import SwiftUI
import WatchConnectivity
import AppIntents

@main
struct MyAIssistantWatchApp: App {
    private var connectivityManager = WatchConnectivityManager.shared
    @State private var selectedTab: WatchTab = .compass
    @State private var showVoiceChat = false
    @State private var showAddTask = false

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                // Tab 1: Compass Dashboard
                NavigationStack {
                    WatchCompassView(connectivity: connectivityManager)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showVoiceChat = true
                                } label: {
                                    Image(systemName: "mic.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.accentColor)
                                }
                                .accessibilityLabel("AI Assistant")
                            }
                        }
                        .navigationDestination(isPresented: $showVoiceChat) {
                            WatchVoiceChatView(connectivity: connectivityManager)
                        }
                }
                .tag(WatchTab.compass)

                // Tab 2: Today's Tasks
                NavigationStack {
                    WatchTodayView(connectivity: connectivityManager)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showAddTask = true
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.green)
                                }
                                .accessibilityLabel("Add Task")
                            }
                        }
                        .navigationDestination(isPresented: $showAddTask) {
                            WatchAddTaskView(connectivity: connectivityManager)
                        }
                        .navigationDestination(for: WatchScheduleData.WatchTask.self) { task in
                            WatchTaskDetailView(task: task, connectivity: connectivityManager)
                        }
                }
                .tag(WatchTab.tasks)

                // Tab 3: Quick Check-In
                WatchQuickCheckInView(connectivity: connectivityManager)
                    .tag(WatchTab.checkIn)
            }
            .tabViewStyle(.page)
            .onChange(of: connectivityManager.shouldOpenVoiceChat) { _, shouldOpen in
                if shouldOpen {
                    selectedTab = .compass
                    showVoiceChat = true
                    connectivityManager.shouldOpenVoiceChat = false
                }
            }
            .onOpenURL { url in
                if url.scheme == "myaissistant" && url.host == "voice" {
                    selectedTab = .compass
                    showVoiceChat = true
                }
            }
        }
    }

    enum WatchTab {
        case compass, tasks, checkIn
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
