import SwiftUI
import HabitDesign

@main
struct HabitDotsApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            ConfettiHost {
                TodayView()
            }
            .habitTheme()
            .environment(model)
            .task { await model.start() }
        }
    }
}
