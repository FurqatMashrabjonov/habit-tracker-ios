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

/// Debug builds can pretend to own Pro (Settings), like the Android preview build.
enum Pro {
    #if DEBUG
    static let debuggable = true
    #else
    static let debuggable = false
    #endif
}

extension View {
    /// Text grows with the phone's setting up to the first accessibility size; past it, dot walls, big
    /// numbers and two-button rows stop fitting a phone width. Sheets don't inherit it, so each sets it.
    func textCap() -> some View { dynamicTypeSize(...DynamicTypeSize.accessibility1) }
}
