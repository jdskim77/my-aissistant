import OSLog

/// Centralized logging for the app. Uses Apple's os.log for structured,
/// privacy-aware logging that shows in Console.app and Xcode's debug console.
enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.myaissistant"

    static let data     = Logger(subsystem: subsystem, category: "Data")
    static let sync     = Logger(subsystem: subsystem, category: "Sync")
    static let ai       = Logger(subsystem: subsystem, category: "AI")
    static let calendar = Logger(subsystem: subsystem, category: "Calendar")
    static let general  = Logger(subsystem: subsystem, category: "General")
}
