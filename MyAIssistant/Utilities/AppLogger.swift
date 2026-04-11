import Foundation
import OSLog

/// Centralized logging for the app. Uses Apple's os.log for structured,
/// privacy-aware logging that shows in Console.app and Xcode's debug console.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.thrivn"

    /// App lifecycle: launch, background, foreground, memory warnings
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Navigation: tab switches, sheet presentation, deep links
    static let navigation = Logger(subsystem: subsystem, category: "Navigation")
    /// Task CRUD, completion, deletion
    static let tasks = Logger(subsystem: subsystem, category: "Tasks")
    /// Check-in flow, mood recording
    static let checkIns = Logger(subsystem: subsystem, category: "CheckIns")
    /// AI chat, prompt building, streaming
    static let ai = Logger(subsystem: subsystem, category: "AI")
    /// Network requests, responses, errors
    static let network = Logger(subsystem: subsystem, category: "Network")
    /// SwiftData saves, fetches, migrations
    static let persistence = Logger(subsystem: subsystem, category: "Data")
    /// Calendar sync, EventKit
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    /// WatchConnectivity, Watch sync
    static let watch = Logger(subsystem: subsystem, category: "Watch")
    /// Authentication, Keychain, API keys
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    /// Notifications, scheduling, permissions
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    /// Performance, timing, memory
    static let performance = Logger(subsystem: subsystem, category: "Performance")
    /// General / uncategorized
    static let general = Logger(subsystem: subsystem, category: "General")
    /// Sync (legacy alias)
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    /// Data (legacy alias)
    static let data = Logger(subsystem: subsystem, category: "Data")
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
