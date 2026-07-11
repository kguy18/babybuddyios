import WidgetKit
import SwiftUI

/// Widget extension entry point.
@main
struct BabyBuddyWidgets: WidgetBundle {
    var body: some Widget {
        QuickStartWidget()
        QuickLogWidget()
        ActiveTimerWidget()
        StatusWidget()
        RunningTimerLiveActivity()
    }
}
