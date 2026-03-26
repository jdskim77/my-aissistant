import Foundation

/// Shared data structure written by the main app and read by widgets via App Groups.
struct WidgetData: Codable {
    let tasksCompleted: Int
    let tasksTotal: Int
    let topPending: [WidgetTask]
    let streakDays: Int
    let streakActive: Bool
    let quoteText: String?
    let quoteAuthor: String?
    let updatedAt: Date

    struct WidgetTask: Codable {
        let title: String
        let priority: String
        let time: String?
    }

    static let appGroupID = "group.com.myaissistant.shared"
    static let fileName = "widget-data.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Read the latest data written by the main app.
    static func load() -> WidgetData? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetData.self, from: data)
    }

    /// Write data from the main app.
    func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
