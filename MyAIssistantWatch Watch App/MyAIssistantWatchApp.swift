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
            // Page order: taskList ← tasks (Today) → checkIn. Today remains
            // the default landing; swipe left for the full list, right for
            // the check-in (preserves existing muscle memory for check-in).
            TabView(selection: $selectedTab) {
                NavigationStack {
                    WatchTasksListView(connectivity: connectivityManager)
                        .navigationDestination(for: WatchScheduleData.WatchTask.self) { task in
                            WatchTaskDetailView(task: task, connectivity: connectivityManager)
                        }
                }
                .tag(WatchTab.taskList)

                // Today — vertical progress bars + inline next row +
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

                // Quick Check-In
                WatchQuickCheckInView(connectivity: connectivityManager)
                    .tag(WatchTab.checkIn)
            }
            .tabViewStyle(.page)
            .onChange(of: connectivityManager.shouldOpenVoiceChat) { _, shouldOpen in
                if shouldOpen {
                    presentVoiceChat()
                    connectivityManager.shouldOpenVoiceChat = false
                }
            }
            .onOpenURL { url in
                if url.scheme == "myaissistant" && url.host == "voice" {
                    presentVoiceChat()
                }
            }
        }
    }

    /// `showVoiceChat`'s `navigationDestination` is wired onto the `.tasks`
    /// tab's NavigationStack. If the user is on any other page when the Ask
    /// AI intent fires, setting the binding before SwiftUI has switched tabs
    /// races the destination mount and the push can silently no-op. Switch
    /// tab first, let one run-loop tick pass, then trigger the push.
    private func presentVoiceChat() {
        let wasOnTasksTab = (selectedTab == .tasks)
        selectedTab = .tasks
        if wasOnTasksTab {
            showVoiceChat = true
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                showVoiceChat = true
            }
        }
    }

    enum WatchTab {
        case taskList, tasks, checkIn
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
