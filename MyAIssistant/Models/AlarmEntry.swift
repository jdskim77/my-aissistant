import Foundation
import SwiftData

@Model
final class AlarmEntry {
    var id: String = UUID().uuidString
    var label: String = ""
    var time: Date = Date()
    var repeatsDaily: Bool = false
    var notificationID: String = UUID().uuidString
    var createdAt: Date = Date()

    init(
        id: String = UUID().uuidString,
        label: String,
        time: Date,
        repeatsDaily: Bool = false,
        notificationID: String = UUID().uuidString
    ) {
        self.id = id
        self.label = label
        self.time = time
        self.repeatsDaily = repeatsDaily
        self.notificationID = notificationID
        self.createdAt = Date()
    }
}
