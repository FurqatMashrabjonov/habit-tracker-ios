import SwiftUI
import UserNotifications
import WidgetKit
import HabitData
import GoogleSignIn
import HabitDesign
import HabitDomain
import BackgroundTasks

@main
struct HabitDotsApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel.shared
    @AppStorage("theme") private var theme = ThemeMode.system
    @AppStorage("onboarded") private var onboarded = false
    @State private var store = Store.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ConfettiHost {
                ZStack {
                    TodayView()
                    #if DEBUG
                    if let i = CommandLine.arguments.firstIndex(of: "-widgets") {
                        WidgetGallery(look: CommandLine.arguments.dropFirst(i + 1).first.flatMap(WidgetLook.init(rawValue:)) ?? .auto).zIndex(2)
                    }
                    #endif
                    // First run: over everything, then it fades to the home screen with the picked habits.
                    if !onboarded {
                        OnboardingView { withAnimation(.easeOut(duration: 0.32)) { onboarded = true } }
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }
            }
            .habitTheme(dark: theme.dark)
            .textCap()
            .environment(model)
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.observe(); Sync.shared.request(after: 0) }
                if phase == .background { Refresh.schedule() }
            }
            .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
            .task {
                #if DEBUG
                if CommandLine.arguments.contains("-paywall") { store.paywall = true }
                #endif
                await store.start()
            }
            .sheet(isPresented: $store.paywall) { Paywall() }
        }
        .backgroundTask(.appRefresh(Refresh.id)) { await Refresh.run() }
    }
}

/// While the app isn't opened for days, iOS wakes it now and then: reminders roll forward (only the
/// next few days are scheduled), the other phone's changes come down, widgets redraw.
/// ponytail: iOS picks when, often a few times a day; nothing here depends on it running.
enum Refresh {
    static let id = "app.habitdots.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor static func run() async {
        schedule()
        await Reminders.rebuild(AppModel.shared.store, today: .today)
        try? await Sync.shared.run()
        WidgetCenter.shared.reloadAllTimelines()
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
