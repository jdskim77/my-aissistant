import SwiftData
import OSLog

extension ModelContext {
    /// Save with error logging. Use instead of `try? modelContext.save()`.
    /// Returns true on success, false on failure (and logs the error).
    @discardableResult
    func safeSave(file: String = #file, line: Int = #line) -> Bool {
        do {
            try save()
            return true
        } catch {
            let fileName = (file as NSString).lastPathComponent
            AppLogger.data.error("Save failed at \(fileName):\(line) — \(error.localizedDescription)")
            return false
        }
    }
}
