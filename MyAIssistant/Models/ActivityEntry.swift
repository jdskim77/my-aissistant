import Foundation
import SwiftData

@Model
final class ActivityEntry {
    var id: String
    var activity: String
    var category: String
    var date: Date
    var source: String

    init(
        id: String = UUID().uuidString,
        activity: String,
        category: String,
        date: Date = Date(),
        source: String = "chat"
    ) {
        self.id = id
        self.activity = activity
        self.category = category
        self.date = date
        self.source = source
    }
}
