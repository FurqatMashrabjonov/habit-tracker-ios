import SwiftUI
import UserNotifications
import HabitDesign

@main
struct HabitDotsApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Before launch finishes, so a Done tapped while the app wasn't running is delivered.
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        Reminders.registerCategories()
        return true
    }
}
