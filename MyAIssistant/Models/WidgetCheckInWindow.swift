import Foundation

/// Shared data model for passing check-in window info to the widget via App Group.
/// This struct is also defined in the Widgets target — keep both in sync.
struct WidgetCheckInWindow: Codable {
    let name: String
    let hour: Int
    let minute: Int
    let greeting: String
}
