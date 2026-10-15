import SwiftUI
import HabitDesign

@main
struct HabitDotsApp: App {
    @State private var model = AppModel.live()
    @AppStorage("theme") private var theme = ThemeMode.system
    @AppStorage("onboarded") private var onboarded = false

    var body: some Scene {
        WindowGroup {
            ConfettiHost {
                ZStack {
                    TodayView()
                    // First run: over everything, then it fades to the home screen with the picked habits.
                    if !onboarded {
                        OnboardingView { withAnimation(.easeOut(duration: 0.32)) { onboarded = true } }
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
            }
            .habitTheme(dark: theme.dark)
            .environment(model)
            .task { await model.start() }
        }
    }
}
