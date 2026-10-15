import SwiftUI
import HabitDesign

@main
struct HabitDotsApp: App {
    @State private var model = AppModel.live()
    @AppStorage("theme") private var theme = ThemeMode.system

    var body: some Scene {
        WindowGroup {
            ConfettiHost {
                TodayView()
            }
            .habitTheme(dark: theme.dark)
            .environment(model)
            .task { await model.start() }
        }
    }
}
