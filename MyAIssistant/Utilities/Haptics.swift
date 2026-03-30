import UIKit

/// Centralized haptic feedback for consistent tactile responses across the app.
enum Haptics {
    /// Light tap — task completion, selection changes, positive actions
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap — warnings, mic toggle, significant state changes
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy tap — destructive actions (delete)
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Success notification — task completed, form submitted
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Selection changed — tab switch, filter pill, picker
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
