import SwiftUI
import WidgetKit

@main
struct HabitDotsWidgets: WidgetBundle {
    var body: some Widget {
        HabitWidget()
        ChecklistWidget()
        InboxWidget()
    }
}
