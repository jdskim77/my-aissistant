import SwiftData
import OSLog

extension ModelContext {
    /// Save with error logging. Use instead of `try? modelContext.save()`.
    func safeSave(file: String = #file, line: Int = #line) {
        do {
            try save()
        } catch {
            let fileName = (file as NSString).lastPathComponent
            AppLogger.data.error("Save failed at \(fileName):\(line) — \(error.localizedDescription)")
        }
    }
}
