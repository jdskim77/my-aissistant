#if os(watchOS)
import WidgetKit
import SwiftUI

struct MyAIssistantWatchWidgets: WidgetBundle {
    var body: some Widget {
        NextEventComplication()
        StreakComplication()
        CompletionRingComplication()
    }
}

#endif
