import Foundation
import SwiftData

@Model
final class AlarmEntry {
    var id: String
    var label: String
    var time: Date
    var repeatsDaily: Bool
    var notificationID: String
    var createdAt: Date

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
