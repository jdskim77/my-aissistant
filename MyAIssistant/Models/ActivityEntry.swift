import Foundation
import SwiftData

@Model
final class ActivityEntry {
    var id: String = UUID().uuidString
    var activity: String = ""
    var category: String = ""
    var date: Date = Date()
    var source: String = "chat"

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
