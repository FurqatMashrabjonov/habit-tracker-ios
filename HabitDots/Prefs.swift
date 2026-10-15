import SwiftUI

enum ThemeMode: String, CaseIterable { case system, light, dark
    var label: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    /// nil follows the phone.
    var dark: Bool? { switch self { case .system: nil; case .light: false; case .dark: true } }
}

/// Habit cards on the home screen: the full wall (free), the last week, or just name and check (Pro).
enum CardStyle: String, CaseIterable { case wall, compact, minimal
    var label: String { switch self { case .wall: "Dot wall"; case .compact: "Last 7 days"; case .minimal: "Name only" } }
}

/// HabitDots Pro. ponytail: StoreKit comes with the Pro phase; until then only debug builds can switch
/// it on (Settings › Pretend Pro), like the Android preview build.
enum Pro {
    static let freeHabits = 5
    static var active: Bool { UserDefaults.standard.bool(forKey: "pretendPro") }
    #if DEBUG
    static let debuggable = true
    #else
    static let debuggable = false
    #endif
}
