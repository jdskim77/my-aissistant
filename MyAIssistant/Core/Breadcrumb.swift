import Foundation
import os.log

/// Lightweight breadcrumb trail for crash context. Stores the last 100
/// user actions in a ring buffer. When Sentry is integrated, breadcrumbs
/// are forwarded automatically — until then, the buffer is available via
/// `recentDescription()` for manual attachment to error reports.
enum Breadcrumb {
    private static var buffer: [(Date, String, String)] = []
    private static let maxBreadcrumbs = 100
    private static let lock = NSLock()

    static func add(category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append((Date(), category, message))
        if buffer.count > maxBreadcrumbs { buffer.removeFirst() }
    }

    /// Dump recent breadcrumbs as a string for error reports.
    static func recentDescription(last n: Int = 20) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return buffer.suffix(n).map { (date, cat, msg) in
            "[\(formatter.string(from: date))] [\(cat)] \(msg)"
        }.joined(separator: "\n")
    }

    /// Clear all breadcrumbs (e.g., on sign-out).
    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
