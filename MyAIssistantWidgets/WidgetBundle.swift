import WidgetKit
import SwiftUI

// NOTE: This file is part of the Widget Extension target.
// To activate widgets, add a Widget Extension target in Xcode:
// File > New > Target > Widget Extension
// Then move these files to the widget target and configure the App Group.

@main
struct MyAIssistantWidgets: WidgetBundle {
    var body: some Widget {
        NextCheckInWidget()
        TodayProgressWidget()
        StreakWidget()
    }
}
